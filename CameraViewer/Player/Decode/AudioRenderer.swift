import AVFoundation
import CoreMedia

/// Plays AAC access units through an `AVSampleBufferAudioRenderer` driven by its own
/// `AVSampleBufferRenderSynchronizer`. Kept independent of the video display layer so the
/// video path stays on its zero-latency DisplayImmediately route — audio rides its own
/// clock, started at the first frame's PTS. Both sides sit at the live edge, so they stay
/// roughly aligned without a shared timebase.
final class AudioRenderer {
    private let renderer = AVSampleBufferAudioRenderer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private let formatDescription: CMAudioFormatDescription?
    private let sampleRate: Int
    private var started = false
    private var baseTimestamp: UInt32?   // first RTP ts → timeline is rebased to start at 0

    init?(config: AudioSpecificConfig, muted: Bool) {
        self.sampleRate = config.sampleRate
        self.formatDescription = Self.makeFormatDescription(config: config)
        guard formatDescription != nil else { return nil }
        synchronizer.addRenderer(renderer)
        renderer.isMuted = muted
    }

    func setMuted(_ muted: Bool) { renderer.isMuted = muted }

    func enqueue(_ frame: AACFrame) {
        guard let formatDescription else { return }
        if baseTimestamp == nil { baseTimestamp = frame.timestamp }
        guard renderer.isReadyForMoreMediaData,
              let sampleBuffer = makeSampleBuffer(frame, format: formatDescription) else { return }
        renderer.enqueue(sampleBuffer)
        if !started {
            started = true
            // Zero-based timeline: huge raw RTP timestamps (~hours) prevent the audio
            // renderer from locking and playing, so we start the clock at 0.
            synchronizer.setRate(1.0, time: .zero)
        }
    }

    /// PTS rebased so the first frame is at t=0.
    private func presentationTime(for timestamp: UInt32) -> CMTime {
        let base = baseTimestamp ?? timestamp
        let delta = Int64(bitPattern: UInt64(timestamp) &- UInt64(base))
        return CMTime(value: delta, timescale: CMTimeScale(sampleRate))
    }

    func reset() {
        synchronizer.setRate(0, time: .zero)
        renderer.flush()
        started = false
        baseTimestamp = nil
    }

    // MARK: - CoreMedia plumbing

    private static func makeFormatDescription(config: AudioSpecificConfig) -> CMAudioFormatDescription? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Float64(config.sampleRate),
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: AudioFormatFlags(MPEG4ObjectID.AAC_LC.rawValue),
            mBytesPerPacket: 0,
            mFramesPerPacket: 1024,             // one AAC-LC frame = 1024 samples
            mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(config.channels),
            mBitsPerChannel: 0,
            mReserved: 0)

        var format: CMAudioFormatDescription?
        let cookie = [UInt8](config.bytes)
        let status = cookie.withUnsafeBytes { cookiePtr in
            CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                asbd: &asbd,
                layoutSize: 0, layout: nil,
                magicCookieSize: cookie.count,
                magicCookie: cookiePtr.baseAddress,
                extensions: nil,
                formatDescriptionOut: &format)
        }
        if status != noErr { AppLog.decode.error("Audio format description failed: \(status)") }
        return format
    }

    private func makeSampleBuffer(_ frame: AACFrame, format: CMAudioFormatDescription) -> CMSampleBuffer? {
        let length = frame.data.count
        let memory = malloc(length)!
        frame.data.copyBytes(to: memory.assumingMemoryBound(to: UInt8.self), count: length)

        var blockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: memory, blockLength: length,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: length, flags: 0, blockBufferOut: &blockBuffer)
        guard status == noErr, let blockBuffer else { free(memory); return nil }

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1024, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: presentationTime(for: frame.timestamp),
            decodeTimeStamp: .invalid)
        var sampleSize = length
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: blockBuffer,
            formatDescription: format, sampleCount: 1,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer)
        guard status == noErr else { return nil }
        return sampleBuffer
    }
}

import AVFoundation
import CoreMedia
import VideoToolbox

/// Turns reassembled NAL units into `CMSampleBuffer`s and enqueues them on an
/// `AVSampleBufferDisplayLayer`. Builds the H.264/H.265 `CMVideoFormatDescription`
/// from parameter-set NALs (cached, rebuilt only when they change), converts each
/// access unit to 4-byte length-prefixed (AVCC/HVCC) form, and tags it
/// DisplayImmediately for lowest latency.
final class VideoDecoder {
    enum Codec { case h264, h265 }

    private let layer: AVSampleBufferDisplayLayer
    private let codec: Codec
    private var formatDescription: CMVideoFormatDescription?
    private var parameterSets: [Data] = []
    private var accessUnit = Data()
    private var firstFrameDecoded = false

    var onFirstFrame: (() -> Void)?
    /// Reports the decoded video dimensions once the format description is built.
    var onVideoSize: ((CGSize) -> Void)?

    init(layer: AVSampleBufferDisplayLayer, codec: Codec) {
        self.layer = layer
        self.codec = codec
    }

    /// Seed parameter sets from the SDP `sprop-*` fields (available before any RTP).
    func setParameterSets(_ sets: [Data]) {
        guard !sets.isEmpty, sets != parameterSets else { return }
        parameterSets = sets
        rebuildFormatDescription()
    }

    /// Feed one reassembled NAL unit. Parameter-set NALs update the format description;
    /// VCL NALs accumulate into the current access unit, flushed on the AU boundary.
    func handle(_ nal: NALUnit) {
        let type = nalType(nal.data)
        if isParameterSet(type) {
            updateParameterSet(nal.data, type: type)
            return
        }
        // Length-prefix this NAL (4-byte big-endian) and append to the access unit.
        var length = UInt32(nal.data.count).bigEndian
        withUnsafeBytes(of: &length) { accessUnit.append(contentsOf: $0) }
        accessUnit.append(nal.data)

        if nal.isAccessUnitEnd {
            flush(timestamp: nal.timestamp)
        }
    }

    func reset() {
        accessUnit.removeAll(keepingCapacity: true)
        if #available(macOS 14.0, *) {
            layer.sampleBufferRenderer.flush(removingDisplayedImage: true) {}
        } else {
            layer.flushAndRemoveImage()
        }
        formatDescription = nil
        parameterSets = []
        firstFrameDecoded = false
    }

    // MARK: - NAL classification

    private func nalType(_ data: Data) -> Int {
        guard let first = data.first else { return -1 }
        return codec == .h264 ? Int(first & 0x1f) : Int((first >> 1) & 0x3f)
    }

    private func isParameterSet(_ type: Int) -> Bool {
        codec == .h264 ? (type == 7 || type == 8)            // SPS, PPS
                       : (type == 32 || type == 33 || type == 34)  // VPS, SPS, PPS
    }

    private func updateParameterSet(_ data: Data, type: Int) {
        // Maintain ordered, de-duplicated parameter sets.
        let slotOrder: [Int] = codec == .h264 ? [7, 8] : [32, 33, 34]
        var byType: [Int: Data] = [:]
        for set in parameterSets { byType[nalType(set)] = set }
        byType[type] = data
        let ordered = slotOrder.compactMap { byType[$0] }
        guard ordered.count == slotOrder.count, ordered != parameterSets else {
            if ordered.count == slotOrder.count { parameterSets = ordered }
            return
        }
        parameterSets = ordered
        rebuildFormatDescription()
    }

    private func rebuildFormatDescription() {
        let pointers = parameterSets.map { [UInt8]($0) }
        guard pointers.count >= 2 else { return }

        var format: CMFormatDescription?
        let status: OSStatus = pointers.withUnsafeBufferPointerToPointers { count, ptrs, sizes in
            if codec == .h264 {
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: count,
                    parameterSetPointers: ptrs, parameterSetSizes: sizes,
                    nalUnitHeaderLength: 4, formatDescriptionOut: &format)
            } else {
                return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: count,
                    parameterSetPointers: ptrs, parameterSetSizes: sizes,
                    nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &format)
            }
        }
        if status == noErr, let format {
            formatDescription = format
            let dims = CMVideoFormatDescriptionGetDimensions(format)
            onVideoSize?(CGSize(width: Int(dims.width), height: Int(dims.height)))
        } else {
            AppLog.decode.error("Video format description failed: \(status)")
        }
    }

    private func flush(timestamp: UInt32) {
        defer { accessUnit.removeAll(keepingCapacity: true) }
        guard let formatDescription, !accessUnit.isEmpty else { return }

        var blockBuffer: CMBlockBuffer?
        let au = accessUnit
        let auLength = au.count
        let memory = malloc(auLength)!
        au.copyBytes(to: memory.assumingMemoryBound(to: UInt8.self), count: auLength)

        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: memory, blockLength: auLength,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: auLength, flags: 0, blockBufferOut: &blockBuffer)
        guard status == noErr, let blockBuffer else { free(memory); return }

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: CMTimeValue(timestamp), timescale: 90000),
            decodeTimeStamp: .invalid)
        var sampleSize = auLength
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: blockBuffer,
            formatDescription: formatDescription, sampleCount: 1,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer)
        guard status == noErr, let sampleBuffer else { return }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }

        enqueue(sampleBuffer)
    }

    private func enqueue(_ sampleBuffer: CMSampleBuffer) {
        if #available(macOS 14.0, *) {
            if layer.sampleBufferRenderer.status == .failed { layer.sampleBufferRenderer.flush() }
            layer.sampleBufferRenderer.enqueue(sampleBuffer)
        } else {
            if layer.status == .failed { layer.flush() }
            layer.enqueue(sampleBuffer)
        }
        if !firstFrameDecoded {
            firstFrameDecoded = true
            DispatchQueue.main.async { [weak self] in self?.onFirstFrame?() }
        }
    }
}

private extension Array where Element == [UInt8] {
    /// Bridges `[[UInt8]]` into the C `(pointers[], sizes[])` pair the VideoToolbox
    /// parameter-set APIs require, keeping the backing storage alive for the call.
    func withUnsafeBufferPointerToPointers<R>(
        _ body: (Int, UnsafePointer<UnsafePointer<UInt8>>, UnsafePointer<Int>) -> R
    ) -> R {
        var pointers: [UnsafePointer<UInt8>] = []
        var sizes: [Int] = []
        var buffers: [UnsafeMutableBufferPointer<UInt8>] = []
        for bytes in self {
            let buf = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: bytes.count)
            _ = buf.initialize(from: bytes)
            buffers.append(buf)
            pointers.append(UnsafePointer(buf.baseAddress!))
            sizes.append(bytes.count)
        }
        defer { buffers.forEach { $0.deallocate() } }
        let count = pointers.count
        return pointers.withUnsafeBufferPointer { pp in
            sizes.withUnsafeBufferPointer { sp in
                body(count, pp.baseAddress!, sp.baseAddress!)
            }
        }
    }
}

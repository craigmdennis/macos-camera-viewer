import AppKit
import AVFoundation
import Combine

/// Drop-in replacement for the VLC-based `CameraPlayer`. Owns the native pipeline:
/// `RTSPClient` (TLS+RTSP+RTP) → depacketizers → `VideoDecoder`/`AudioRenderer` →
/// `AVSampleBufferDisplayLayer` + `AVSampleBufferAudioRenderer`. Exposes the same surface
/// `PiPWindowController` consumes (`state`, `isMuted`, `videoSize`, `play`, `stop`,
/// `setMuted`) so the rest of the app is unchanged.
final class NativeCameraPlayer: NSObject {
    enum State: Equatable {
        case idle, opening, playing, buffering, error(message: String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isMuted: Bool

    private let view: SampleBufferView
    private var client: RTSPClient?
    private var decoder: VideoDecoder?
    private let h264 = H264Depacketizer()
    private let h265 = H265Depacketizer()
    private var codec: VideoDecoder.Codec = .h264
    private var pendingVideoSize: CGSize?
    private var audioRenderer: AudioRenderer?

    init(view: SampleBufferView, initiallyMuted: Bool) {
        self.view = view
        self.isMuted = initiallyMuted
        super.init()
    }

    var videoSize: CGSize? { pendingVideoSize }

    func play(url: URL) {
        stop()
        state = .opening

        let decoder = VideoDecoder(layer: view.displayLayer, codec: .h264)
        decoder.onFirstFrame = { [weak self] in self?.setState(.playing) }
        decoder.onVideoSize = { [weak self] size in self?.pendingVideoSize = size }
        self.decoder = decoder

        let client = RTSPClient(url: url)
        client.onState = { [weak self] s in self?.handleClientState(s) }
        client.onSDP = { [weak self] sdp in self?.applySDP(sdp) }
        client.onVideoRTP = { [weak self] packet in self?.handleVideoRTP(packet) }
        client.onAudioRTP = { [weak self] packet in self?.handleAudioRTP(packet) }
        self.client = client
        client.start()
    }

    func stop() {
        client?.stop()
        client = nil
        decoder?.reset()
        decoder = nil
        audioRenderer?.reset()
        audioRenderer = nil
        h264.reset()
        h265.reset()
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        audioRenderer?.setMuted(muted)
    }

    // MARK: - Plumbing

    private func applySDP(_ sdp: SDPInfo) {
        guard let video = sdp.video else {
            setState(.error(message: "no video track in SDP"))
            return
        }
        codec = video.isH265 ? .h265 : .h264
        let decoder = VideoDecoder(layer: view.displayLayer, codec: codec)
        decoder.onFirstFrame = { [weak self] in self?.setState(.playing) }
        decoder.onVideoSize = { [weak self] size in self?.pendingVideoSize = size }
        decoder.setParameterSets(video.parameterSets)
        self.decoder = decoder

        // Build the audio renderer from the selected (AAC) track's AudioSpecificConfig.
        if let audio = sdp.audio, audio.isAAC,
           let configHex = audio.fmtp["config"],
           let asc = AudioSpecificConfig(hex: configHex) {
            audioRenderer = AudioRenderer(config: asc, muted: isMuted)
        }

        setState(.buffering)
    }

    private func handleVideoRTP(_ packet: RTPPacket) {
        let nals = codec == .h265 ? h265.depacketize(packet) : h264.depacketize(packet)
        for nal in nals { decoder?.handle(nal) }
    }

    private func handleAudioRTP(_ packet: RTPPacket) {
        for frame in AACDepacketizer.depacketize(packet) { audioRenderer?.enqueue(frame) }
    }

    private func handleClientState(_ s: RTSPClient.State) {
        switch s {
        case .idle, .handshaking: break
        case .playing: break   // wait for first decoded frame to flip to .playing
        case .failed(let message): setState(.error(message: message))
        }
    }

    private func setState(_ newState: State) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.state != newState else { return }
            if case .error(let message) = newState {
                AppLog.rtsp.error("Player error: \(message, privacy: .public)")
            } else {
                AppLog.rtsp.notice("Player state: \(String(describing: newState), privacy: .public)")
            }
            self.state = newState
        }
    }
}

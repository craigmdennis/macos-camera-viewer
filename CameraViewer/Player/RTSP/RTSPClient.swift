import Foundation

/// Drives the RTSP control handshake over an `RTSPConnection`:
/// OPTIONS → DESCRIBE → SETUP (video, +audio) → PLAY, with interleaved TCP transport.
/// Parsed RTP packets are routed to the caller by track via `onVideoRTP`/`onAudioRTP`.
/// No auth path: capture confirmed UniFi answers `200` with the URL token alone.
///
/// The handshake is an explicit step machine — each reply is matched to the request that
/// produced it (`pending`), not inferred from accumulated state. Interleaved channel
/// numbers are taken from the server's echoed `Transport` header, since servers may
/// assign different channels than requested.
final class RTSPClient {
    enum State: Equatable { case idle, handshaking, playing, failed(String) }

    private enum Step: Equatable {
        case options, describe, setup(trackIndex: Int), play
    }

    private let url: URL
    private let baseURI: String          // rtsp(s)://host:port/path  (no ?enableSrtp)
    private var connection: RTSPConnection?
    private var cseq = 0
    private var session: String?
    private var contentBase: String?
    private var pending: Step?

    private var setupTracks: [SDPMedia] = []
    private var setupIndex = 0
    private var requestedChannel: UInt8 = 0   // low channel we asked for in the current SETUP
    private var videoChannel: UInt8?
    private var audioChannel: UInt8?
    private var keepaliveTimer: Timer?

    var onState: ((State) -> Void)?
    var onSDP: ((SDPInfo) -> Void)?
    var onVideoRTP: ((RTPPacket) -> Void)?
    var onAudioRTP: ((RTPPacket) -> Void)?

    init(url: URL) {
        // Strip ?enableSrtp — we use plain RTP inside the TLS tunnel.
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.query = nil
        self.url = url
        self.baseURI = comps?.string ?? url.absoluteString
    }

    func start() {
        let host = url.host ?? "127.0.0.1"
        let port = UInt16(url.port ?? 7441)
        let conn = RTSPConnection(host: host, port: port)
        connection = conn
        onState?(.handshaking)
        conn.onEvent = { [weak self] event in self?.handle(event) }
        conn.start()
    }

    func stop() {
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
        if session != nil { send(.options, method: "TEARDOWN", uri: baseURI) }
        connection?.stop()
        connection = nil
        session = nil
        pending = nil
    }

    private func handle(_ event: RTSPConnection.Event) {
        switch event {
        case .ready:
            send(.options, method: "OPTIONS", uri: baseURI)
        case .response(let response):
            handleResponse(response)
        case .interleaved(let channel, let payload):
            guard let packet = RTPPacket(payload) else { return }
            if channel == videoChannel { onVideoRTP?(packet) }
            else if channel == audioChannel { onAudioRTP?(packet) }
        case .failed(let error):
            onState?(.failed(error.localizedDescription))
        case .closed:
            onState?(.failed("connection closed"))
        }
    }

    private func handleResponse(_ response: RTSPResponse) {
        guard response.isOK else {
            onState?(.failed("RTSP \(response.statusCode)"))
            return
        }
        if let s = response.session { session = s }

        switch pending {
        case .options:
            send(.describe, method: "DESCRIBE", uri: baseURI, headers: ["Accept": "application/sdp"])

        case .describe:
            contentBase = response.contentBase ?? baseURI
            let parsed = SDPParser.parse(response.body)
            onSDP?(parsed)
            setupTracks = [parsed.video, parsed.audio].compactMap { $0 }
            setupIndex = 0
            guard !setupTracks.isEmpty else { onState?(.failed("no media tracks")); return }
            setupNextTrack()

        case .setup(let trackIndex):
            // Record the channel the server actually assigned for this track.
            let channel = Self.interleavedChannel(from: response.headers["transport"]) ?? requestedChannel
            if setupTracks[trackIndex].kind == .video { videoChannel = channel }
            else { audioChannel = channel }

            setupIndex += 1
            if setupIndex < setupTracks.count {
                setupNextTrack()
            } else {
                send(.play, method: "PLAY", uri: contentBase ?? baseURI,
                     headers: ["Range": "npt=0.000-"])
            }

        case .play:
            onState?(.playing)
            startKeepalive()

        case .none:
            break
        }
    }

    private func setupNextTrack() {
        let media = setupTracks[setupIndex]
        // Two interleaved channels per track: video 0-1, audio 2-3.
        let lo = UInt8(setupIndex * 2)
        requestedChannel = lo
        let trackURI = resolveControl(media.control)
        send(.setup(trackIndex: setupIndex), method: "SETUP", uri: trackURI,
             headers: ["Transport": "RTP/AVP/TCP;unicast;interleaved=\(lo)-\(lo + 1)"])
    }

    /// Parse `interleaved=N-M` out of a Transport header, returning N.
    private static func interleavedChannel(from transport: String?) -> UInt8? {
        guard let transport,
              let range = transport.range(of: "interleaved=") else { return nil }
        let rest = transport[range.upperBound...]
        let digits = rest.prefix { $0.isNumber }
        return UInt8(digits)
    }

    private func resolveControl(_ control: String?) -> String {
        guard let control, control != "*" else { return contentBase ?? baseURI }
        if control.hasPrefix("rtsp://") || control.hasPrefix("rtsps://") { return control }
        let base = (contentBase ?? baseURI)
        return base.hasSuffix("/") ? base + control : base + "/" + control
    }

    /// Periodic GET_PARAMETER keepalive so the server doesn't close an idle session.
    private func startKeepalive() {
        keepaliveTimer?.invalidate()
        keepaliveTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            guard let self, self.session != nil else { return }
            self.send(.play, method: "GET_PARAMETER", uri: self.contentBase ?? self.baseURI)
        }
    }

    private func send(_ step: Step, method: String, uri: String, headers: [String: String] = [:]) {
        pending = step
        cseq += 1
        var allHeaders = headers
        if let session { allHeaders["Session"] = session }
        connection?.send(RTSPRequest(method: method, uri: uri, cseq: cseq, headers: allHeaders))
    }
}

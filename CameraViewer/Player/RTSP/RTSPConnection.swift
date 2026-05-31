import Foundation
import Network

/// TLS TCP connection to the RTSP server with RTSP-over-TCP interleaved framing
/// (RFC 2326 §10.12). Demultiplexes the byte stream into RTSP responses (text) and
/// `$`-framed binary RTP packets, delivered via callbacks on `queue`.
///
/// TLS certificate verification is disabled: UniFi NVRs present a self-signed cert with
/// no IP SAN, so verification can never succeed — go2rtc's `rtspx://` does the same. The
/// link is still encrypted; we just don't authenticate the server beyond LAN reachability.
final class RTSPConnection {
    enum Event {
        case ready
        case response(RTSPResponse)
        case interleaved(channel: UInt8, payload: Data)
        case failed(Error)
        case closed
    }

    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "rtsp.connection")
    private var connection: NWConnection?
    /// Unconsumed received bytes. Kept as `[UInt8]` with integer offsets to avoid
    /// `Data` slice-index pitfalls when consuming from the front.
    private var buffer: [UInt8] = []
    var onEvent: ((Event) -> Void)?

    init(host: String, port: UInt16) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    func start() {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(
            tls.securityProtocolOptions,
            { _, _, complete in complete(true) },   // accept self-signed cert
            queue
        )
        let params = NWParameters(tls: tls, tcp: .init())
        let connection = NWConnection(host: host, port: port, using: params)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onEvent?(.ready)
                self?.receive()
            case .failed(let error):
                self?.onEvent?(.failed(error))
            case .cancelled:
                self?.onEvent?(.closed)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func send(_ request: RTSPRequest) {
        let data = Data(request.serialized().utf8)
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    func stop() {
        connection?.cancel()
        connection = nil
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(contentsOf: data)
                self.drain()
            }
            if let error { self.onEvent?(.failed(error)); return }
            if isComplete { self.onEvent?(.closed); return }
            self.receive()
        }
    }

    /// Consume as many complete frames as are buffered. A frame is either a `$`-prefixed
    /// interleaved RTP packet (4-byte header + payload) or a full RTSP text response
    /// (headers terminated by CRLFCRLF, plus a Content-Length body). Anything incomplete
    /// is left in `buffer` for the next receive.
    private func drain() {
        var offset = 0
        while offset < buffer.count {
            if buffer[offset] == 0x24 {                      // '$' interleaved
                guard offset + 4 <= buffer.count else { break }
                let channel = buffer[offset + 1]
                let length = Int(buffer[offset + 2]) << 8 | Int(buffer[offset + 3])
                guard offset + 4 + length <= buffer.count else { break }
                let payload = Data(buffer[(offset + 4) ..< (offset + 4 + length)])
                offset += 4 + length
                onEvent?(.interleaved(channel: channel, payload: payload))
            } else {                                          // RTSP text response
                guard let headerEnd = doubleCRLF(from: offset) else { break }   // need full headers
                let header = String(decoding: buffer[offset ..< headerEnd], as: UTF8.self)
                let bodyLength = Self.contentLength(in: header)
                let frameEnd = headerEnd + bodyLength
                guard frameEnd <= buffer.count else { break }                   // need full body
                let full = String(decoding: buffer[offset ..< frameEnd], as: UTF8.self)
                offset = frameEnd
                if let response = RTSPResponse.parse(full) {
                    onEvent?(.response(response))
                }
            }
        }
        if offset > 0 { buffer.removeFirst(offset) }
    }

    /// Index just past the first CRLFCRLF at or after `start`, or nil if not yet present.
    private func doubleCRLF(from start: Int) -> Int? {
        guard buffer.count >= 4 else { return nil }
        var i = start
        while i <= buffer.count - 4 {
            if buffer[i] == 0x0D, buffer[i + 1] == 0x0A, buffer[i + 2] == 0x0D, buffer[i + 3] == 0x0A {
                return i + 4
            }
            i += 1
        }
        return nil
    }

    private static func contentLength(in header: String) -> Int {
        // `.isNewline` matches the CRLF grapheme cluster; `$0 == "\r"||"\n"` would not.
        for line in header.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                return Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }
}

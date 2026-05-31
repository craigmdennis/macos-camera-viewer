import Foundation

/// An outgoing RTSP/1.0 request. Serialized as CRLF-terminated text.
struct RTSPRequest {
    let method: String
    let uri: String
    let cseq: Int
    var headers: [String: String] = [:]
    var body: String?

    func serialized(userAgent: String = "CameraViewer") -> String {
        var lines = ["\(method) \(uri) RTSP/1.0", "CSeq: \(cseq)", "User-Agent: \(userAgent)"]
        for key in headers.keys.sorted() { lines.append("\(key): \(headers[key]!)") }
        if let body, !body.isEmpty {
            lines.append("Content-Length: \(body.utf8.count)")
            return lines.joined(separator: "\r\n") + "\r\n\r\n" + body
        }
        return lines.joined(separator: "\r\n") + "\r\n\r\n"
    }
}

/// A parsed RTSP/1.0 response. Header keys are lowercased for case-insensitive lookup.
struct RTSPResponse: Equatable {
    let statusCode: Int
    let headers: [String: String]
    let body: String

    var isOK: Bool { statusCode == 200 }
    var cseq: Int? { headers["cseq"].flatMap { Int($0) } }
    /// `Content-Base` (preferred) or `Content-Location`, used to resolve track SETUP URLs.
    var contentBase: String? { headers["content-base"] ?? headers["content-location"] }
    /// `Session` header value with any `;timeout=…` stripped.
    var session: String? {
        headers["session"]?.split(separator: ";").first.map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    static func parse(_ text: String) -> RTSPResponse? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let head: String, body: String
        if let sep = normalized.range(of: "\n\n") {
            head = String(normalized[..<sep.lowerBound])
            body = String(normalized[sep.upperBound...])
        } else {
            head = normalized
            body = ""
        }
        var lines = head.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty else { return nil }

        let statusParts = lines.removeFirst().split(separator: " ")
        guard statusParts.count >= 2, statusParts[0].hasPrefix("RTSP/"),
              let code = Int(statusParts[1]) else { return nil }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let val = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = val
        }
        return RTSPResponse(statusCode: code, headers: headers, body: body)
    }
}

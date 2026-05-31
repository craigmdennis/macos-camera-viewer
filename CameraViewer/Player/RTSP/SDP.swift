import Foundation

/// One `m=` media section parsed from an RTSP DESCRIBE SDP body. Attributes
/// (`rtpmap`/`fmtp`/`control`/`crypto`) are bound to the section they appear under —
/// payload types repeat across sections, so they must never be used as a global key.
struct SDPMedia: Equatable {
    enum Kind: String { case video, audio }
    let kind: Kind
    let payloadType: Int
    let encoding: String          // "H264", "H265", "mpeg4-generic", "opus", …
    let clockRate: Int
    let channels: Int?
    let control: String?          // e.g. "trackID=2"
    let fmtp: [String: String]    // parsed key=value pairs from a=fmtp
    let hasCrypto: Bool           // a=crypto present → SRTP/SDES offered (we avoid it)

    var isH264: Bool { encoding.caseInsensitiveCompare("H264") == .orderedSame }
    var isH265: Bool {
        encoding.caseInsensitiveCompare("H265") == .orderedSame ||
        encoding.caseInsensitiveCompare("HEVC") == .orderedSame
    }
    var isAAC: Bool {
        encoding.caseInsensitiveCompare("mpeg4-generic") == .orderedSame ||
        encoding.uppercased().contains("AAC")
    }

    /// Decoded parameter-set NAL units: H.264 `sprop-parameter-sets` (SPS,PPS) or
    /// H.265 `sprop-vps`/`sprop-sps`/`sprop-pps`. Empty if none are carried in-SDP.
    var parameterSets: [Data] {
        if let sets = fmtp["sprop-parameter-sets"] {
            return sets.split(separator: ",").compactMap { Data(base64Encoded: String($0)) }
        }
        return ["sprop-vps", "sprop-sps", "sprop-pps"]
            .compactMap { fmtp[$0] }
            .compactMap { Data(base64Encoded: $0) }
    }
}

struct SDPInfo: Equatable {
    let media: [SDPMedia]
    var video: SDPMedia? { media.first { $0.kind == .video } }
    /// Prefer the AAC audio track (natively decodable) over Opus.
    var audio: SDPMedia? {
        media.first { $0.kind == .audio && $0.isAAC } ?? media.first { $0.kind == .audio }
    }
}

enum SDPParser {
    static func parse(_ body: String) -> SDPInfo {
        var media: [SDPMedia] = []
        var section: Builder?

        func flush() {
            if let b = section { media.append(b.build()) }
        }

        // NOTE: `.isNewline` correctly handles CRLF, which Swift represents as a single
        // Character (grapheme cluster) — a naive `$0 == "\r" || $0 == "\n"` would miss it.
        for raw in body.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            if line.hasPrefix("m=") {
                flush()
                section = Builder(mLine: line)
            } else if line.hasPrefix("a="), section != nil {
                section!.apply(attribute: String(line.dropFirst(2)))
            }
        }
        flush()
        return SDPInfo(media: media)
    }

    /// Mutable accumulator for a single media section.
    private struct Builder {
        let kind: SDPMedia.Kind?
        let payloadType: Int
        var encoding = ""
        var clockRate = 0
        var channels: Int?
        var control: String?
        var fmtp: [String: String] = [:]
        var hasCrypto = false

        init(mLine: String) {
            // "m=<kind> <port> <proto> <pt> ..."
            let parts = mLine.dropFirst(2).split(separator: " ")
            kind = parts.first.flatMap { SDPMedia.Kind(rawValue: String($0)) }
            payloadType = parts.count >= 4 ? Int(parts[3]) ?? 0 : 0
        }

        mutating func apply(attribute attr: String) {
            if attr.hasPrefix("rtpmap:") {
                // "rtpmap:96 mpeg4-generic/48000/1"
                guard let value = afterFirstSpace(attr) else { return }
                let comps = value.split(separator: "/")
                if comps.count >= 1 { encoding = String(comps[0]) }
                if comps.count >= 2 { clockRate = Int(comps[1]) ?? 0 }
                if comps.count >= 3 { channels = Int(comps[2]) }
            } else if attr.hasPrefix("fmtp:") {
                // "fmtp:96 key=val; key=val; ..."
                guard let value = afterFirstSpace(attr) else { return }
                for pair in value.split(separator: ";") {
                    let kv = pair.trimmingCharacters(in: .whitespaces)
                    guard let eq = kv.firstIndex(of: "=") else { continue }
                    let key = String(kv[..<eq])
                    let val = String(kv[kv.index(after: eq)...])
                    fmtp[key] = val
                }
            } else if attr.hasPrefix("control:") {
                control = String(attr.dropFirst("control:".count))
            } else if attr.hasPrefix("crypto:") {
                hasCrypto = true
            }
        }

        private func afterFirstSpace(_ s: String) -> Substring? {
            guard let sp = s.firstIndex(of: " ") else { return nil }
            return s[s.index(after: sp)...]
        }

        func build() -> SDPMedia {
            SDPMedia(kind: kind ?? .video, payloadType: payloadType, encoding: encoding,
                     clockRate: clockRate, channels: channels, control: control,
                     fmtp: fmtp, hasCrypto: hasCrypto)
        }
    }
}

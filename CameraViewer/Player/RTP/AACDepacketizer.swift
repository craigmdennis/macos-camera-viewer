import Foundation

/// One AAC access unit (raw AAC frame, no ADTS header) with its RTP timestamp.
struct AACFrame: Equatable {
    let data: Data
    let timestamp: UInt32
}

/// Depacketizes AAC carried as RTP `mpeg4-generic` / AAC-hbr (RFC 3640), matching the
/// camera's `SizeLength=13; IndexLength=3` config: each AU-header is 16 bits (13-bit
/// size + 3-bit index). One or more AUs may follow the AU-header section.
enum AACDepacketizer {
    static func depacketize(_ packet: RTPPacket) -> [AACFrame] {
        let p = [UInt8](packet.payload)
        guard p.count >= 2 else { return [] }

        // AU-headers-length is in BITS; each header here is 16 bits.
        let auHeadersBits = Int(p[0]) << 8 | Int(p[1])
        let headerCount = auHeadersBits / 16
        guard headerCount >= 1 else { return [] }

        var sizes: [Int] = []
        var idx = 2
        for _ in 0 ..< headerCount {
            guard idx + 2 <= p.count else { return [] }
            let header = Int(p[idx]) << 8 | Int(p[idx + 1])
            sizes.append((header >> 3) & 0x1fff)        // top 13 bits = AU size
            idx += 2
        }

        var frames: [AACFrame] = []
        for size in sizes {
            guard size > 0, idx + size <= p.count else { break }
            frames.append(AACFrame(data: Data(p[idx ..< idx + size]), timestamp: packet.timestamp))
            idx += size
        }
        return frames
    }
}

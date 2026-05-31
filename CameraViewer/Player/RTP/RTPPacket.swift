import Foundation

/// A parsed RTP packet header + payload (RFC 3550). Receive-only: we never build these.
/// CSRC list and a header extension (if present) are skipped so `payload` is the
/// codec-specific bytes the depacketizers consume.
struct RTPPacket: Equatable {
    let payloadType: UInt8
    let marker: Bool
    let sequenceNumber: UInt16
    let timestamp: UInt32
    let ssrc: UInt32
    let payload: Data

    init?(_ data: Data) {
        let b = [UInt8](data)
        guard b.count >= 12, (b[0] >> 6) == 2 else { return nil }   // version must be 2

        let csrcCount = Int(b[0] & 0x0f)
        let hasExtension = (b[0] & 0x10) != 0
        marker = (b[1] & 0x80) != 0
        payloadType = b[1] & 0x7f
        sequenceNumber = UInt16(b[2]) << 8 | UInt16(b[3])
        timestamp = UInt32(b[4]) << 24 | UInt32(b[5]) << 16 | UInt32(b[6]) << 8 | UInt32(b[7])
        ssrc = UInt32(b[8]) << 24 | UInt32(b[9]) << 16 | UInt32(b[10]) << 8 | UInt32(b[11])

        var offset = 12 + csrcCount * 4
        guard b.count >= offset else { return nil }
        if hasExtension {
            guard b.count >= offset + 4 else { return nil }
            let extWords = Int(b[offset + 2]) << 8 | Int(b[offset + 3])
            offset += 4 + extWords * 4
            guard b.count >= offset else { return nil }
        }
        payload = Data(b[offset...])
    }
}

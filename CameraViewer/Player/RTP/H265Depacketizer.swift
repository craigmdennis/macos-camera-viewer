import Foundation

/// Reassembles H.265/HEVC NAL units from RTP payloads (RFC 7798). Handles single-NAL,
/// AP aggregation (type 48), and FU fragmentation (type 49). HEVC NAL headers are 2
/// bytes; the camera advertises `sprop-max-don-diff=0`, so no DONL fields are present.
/// Defensive secondary path — the captured cameras stream H.264, not HEVC.
final class H265Depacketizer {
    private var fuBuffer: Data?
    private var fuTimestamp: UInt32 = 0

    func reset() { fuBuffer = nil }

    func depacketize(_ packet: RTPPacket) -> [NALUnit] {
        let p = [UInt8](packet.payload)
        guard p.count >= 2 else { return [] }
        let type = (p[0] >> 1) & 0x3f
        var nals: [Data] = []

        switch type {
        case 0...47:                                   // single NAL unit
            nals = [packet.payload]

        case 48:                                       // AP aggregation
            var i = 2                                   // skip 2-byte payload header
            while i + 2 <= p.count {
                let size = Int(p[i]) << 8 | Int(p[i + 1]); i += 2
                guard size > 0, i + size <= p.count else { break }
                nals.append(Data(p[i ..< i + size]))
                i += size
            }

        case 49:                                       // FU fragmentation
            guard p.count >= 3 else { return [] }
            let fuHeader = p[2]
            let fuType = fuHeader & 0x3f
            if fuHeader & 0x80 != 0 {                   // start
                let h0 = (p[0] & 0x81) | (fuType << 1)  // restore NAL type, keep F + layerId msb
                fuBuffer = Data([h0, p[1]]) + Data(p[3...])
                fuTimestamp = packet.timestamp
            } else if fuBuffer != nil {
                fuBuffer!.append(contentsOf: p[3...])
            }
            guard fuHeader & 0x40 != 0, let buf = fuBuffer else { return [] }   // end
            fuBuffer = nil
            return [NALUnit(data: buf, timestamp: fuTimestamp, isAccessUnitEnd: packet.marker)]

        default:
            return []
        }

        return nals.enumerated().map { idx, data in
            NALUnit(data: data, timestamp: packet.timestamp,
                    isAccessUnitEnd: packet.marker && idx == nals.count - 1)
        }
    }
}

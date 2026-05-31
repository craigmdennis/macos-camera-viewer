import Foundation

/// Reassembles H.264 NAL units from RTP payloads (RFC 6184). Handles single-NAL,
/// STAP-A aggregation, and FU-A fragmentation — the packetization UniFi uses.
/// STAP-B/MTAP/FU-B are not emitted by these cameras and are dropped.
final class H264Depacketizer {
    private var fuBuffer: Data?
    private var fuTimestamp: UInt32 = 0

    func reset() { fuBuffer = nil }

    func depacketize(_ packet: RTPPacket) -> [NALUnit] {
        let p = [UInt8](packet.payload)
        guard let first = p.first else { return [] }
        var nals: [Data] = []

        switch first & 0x1F {
        case 1...23:                                   // single NAL unit
            nals = [packet.payload]

        case 24:                                       // STAP-A aggregation
            var i = 1
            while i + 2 <= p.count {
                let size = Int(p[i]) << 8 | Int(p[i + 1]); i += 2
                guard size > 0, i + size <= p.count else { break }
                nals.append(Data(p[i ..< i + size]))
                i += size
            }

        case 28:                                       // FU-A fragmentation
            guard p.count >= 2 else { return [] }
            let fuHeader = p[1]
            if fuHeader & 0x80 != 0 {                   // start fragment
                let reconstructed = (first & 0xE0) | (fuHeader & 0x1F)
                fuBuffer = Data([reconstructed]) + Data(p[2...])
                fuTimestamp = packet.timestamp
            } else if fuBuffer != nil {                 // middle/end fragment
                fuBuffer!.append(contentsOf: p[2...])
            }
            guard fuHeader & 0x40 != 0, let buf = fuBuffer else { return [] }  // end
            fuBuffer = nil
            nals = [buf]
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

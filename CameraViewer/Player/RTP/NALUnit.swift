import Foundation

/// A complete H.264/H.265 NAL unit emitted by a depacketizer: raw NAL bytes
/// (starting with the NAL header byte(s), no Annex-B start code, no length prefix),
/// tagged with the source RTP timestamp and whether it ends the access unit (frame).
struct NALUnit: Equatable {
    let data: Data
    let timestamp: UInt32
    let isAccessUnitEnd: Bool
}

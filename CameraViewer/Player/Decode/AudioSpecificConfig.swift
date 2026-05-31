import Foundation

/// Parsed MPEG-4 AudioSpecificConfig (ISO 14496-3) from the SDP `fmtp` `config=` hex
/// string. Carries the raw bytes (used as the decoder magic cookie) plus the decoded
/// sample rate and channel count needed to build a `CMAudioFormatDescription`.
struct AudioSpecificConfig: Equatable {
    let bytes: Data
    let sampleRate: Int
    let channels: Int

    private static let frequencies = [
        96000, 88200, 64000, 48000, 44100, 32000, 24000,
        22050, 16000, 12000, 11025, 8000, 7350,
    ]

    init?(hex: String) {
        guard hex.count >= 4, hex.count % 2 == 0 else { return nil }
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index ..< next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        guard data.count >= 2 else { return nil }
        self.bytes = data

        // Bitfields: 5b audioObjectType, 4b samplingFrequencyIndex, 4b channelConfig.
        let b0 = data[0], b1 = data[1]
        let freqIndex = Int(((b0 & 0x07) << 1) | (b1 >> 7))
        guard freqIndex < Self.frequencies.count else { return nil }
        self.sampleRate = Self.frequencies[freqIndex]
        self.channels = Int((b1 >> 3) & 0x0F)
    }
}

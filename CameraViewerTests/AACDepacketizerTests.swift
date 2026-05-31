import XCTest
@testable import CameraViewer

final class AACDepacketizerTests: XCTestCase {
    private func packet(_ payload: [UInt8], ts: UInt32 = 3000) -> RTPPacket {
        var bytes: [UInt8] = [0x80, 96, 0, 1,
                              UInt8(ts >> 24), UInt8((ts >> 16) & 0xff), UInt8((ts >> 8) & 0xff), UInt8(ts & 0xff),
                              0, 0, 0, 1]
        bytes += payload
        return RTPPacket(Data(bytes))!
    }

    func testSingleAU() {
        // AU-headers-length = 16 bits (1 header); size=4 → header = (4<<3)=0x0020; then 4 bytes.
        let frames = AACDepacketizer.depacketize(packet([0x00, 0x10, 0x00, 0x20, 0xDE, 0xAD, 0xBE, 0xEF]))
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].data, Data([0xDE, 0xAD, 0xBE, 0xEF]))
        XCTAssertEqual(frames[0].timestamp, 3000)
    }

    func testTwoAUs() {
        // AU-headers-length = 32 bits (2 headers); sizes 2 and 3.
        let payload: [UInt8] = [0x00, 0x20,
                                0x00, 0x10,            // size 2 = (2<<3)=0x10
                                0x00, 0x18,            // size 3 = (3<<3)=0x18
                                0xAA, 0xBB,            // AU1
                                0x01, 0x02, 0x03]      // AU2
        let frames = AACDepacketizer.depacketize(packet(payload))
        XCTAssertEqual(frames.map(\.data), [Data([0xAA, 0xBB]), Data([0x01, 0x02, 0x03])])
    }

    func testTruncatedReturnsEmpty() {
        XCTAssertTrue(AACDepacketizer.depacketize(packet([0x00])).isEmpty)
    }
}

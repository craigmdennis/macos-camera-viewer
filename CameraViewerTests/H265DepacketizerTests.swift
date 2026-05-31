import XCTest
@testable import CameraViewer

final class H265DepacketizerTests: XCTestCase {
    private func packet(_ payload: [UInt8], ts: UInt32 = 2000, marker: Bool = false) -> RTPPacket {
        var bytes: [UInt8] = [0x80, marker ? (0x80 | 97) : 97, 0, 1,
                              UInt8(ts >> 24), UInt8((ts >> 16) & 0xff), UInt8((ts >> 8) & 0xff), UInt8(ts & 0xff),
                              0, 0, 0, 1]
        bytes += payload
        return RTPPacket(Data(bytes))!
    }

    func testSingleNALPassesThrough() {
        // byte0 0x26 → type (0x26>>1)&0x3f = 19 (single NAL range)
        let nals = H265Depacketizer().depacketize(packet([0x26, 0x01, 0xAA], marker: true))
        XCTAssertEqual(nals.count, 1)
        XCTAssertEqual(nals[0].data, Data([0x26, 0x01, 0xAA]))
        XCTAssertTrue(nals[0].isAccessUnitEnd)
    }

    func testAPYieldsMultipleNALs() {
        // type 48 (0x60,0x01 header), then [size 2][0x40,0x01], [size 1][0x42]
        let nals = H265Depacketizer().depacketize(packet([0x60, 0x01, 0, 2, 0x40, 0x01, 0, 1, 0x42]))
        XCTAssertEqual(nals.map(\.data), [Data([0x40, 0x01]), Data([0x42])])
    }

    func testFUReassemblyReconstructsTwoByteHeader() {
        let dep = H265Depacketizer()
        // FU payload header 0x62,0x01; FU header start 0x93 (S|type19), end 0x53 (E|type19)
        XCTAssertEqual(dep.depacketize(packet([0x62, 0x01, 0x93, 0xAA])).count, 0)
        let done = dep.depacketize(packet([0x62, 0x01, 0x53, 0xBB], marker: true))
        XCTAssertEqual(done.count, 1)
        XCTAssertEqual(done[0].data, Data([0x26, 0x01, 0xAA, 0xBB]))  // type restored to 19
        XCTAssertTrue(done[0].isAccessUnitEnd)
    }

    func testUnknownNothingWhenTooShort() {
        XCTAssertTrue(H265Depacketizer().depacketize(packet([0x60])).isEmpty)
    }
}

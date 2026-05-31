import XCTest
@testable import CameraViewer

final class H264DepacketizerTests: XCTestCase {
    private func packet(_ payload: [UInt8], ts: UInt32 = 1000, marker: Bool = false) -> RTPPacket {
        var bytes: [UInt8] = [0x80, marker ? (0x80 | 96) : 96,
                              0, 1,
                              UInt8(ts >> 24), UInt8((ts >> 16) & 0xff), UInt8((ts >> 8) & 0xff), UInt8(ts & 0xff),
                              0, 0, 0, 1]
        bytes += payload
        return RTPPacket(Data(bytes))!
    }

    func testSingleNALPassesThrough() {
        let dep = H264Depacketizer()
        let nals = dep.depacketize(packet([0x65, 0xAA, 0xBB], marker: true))  // type 5 (IDR)
        XCTAssertEqual(nals.count, 1)
        XCTAssertEqual(nals[0].data, Data([0x65, 0xAA, 0xBB]))
        XCTAssertEqual(nals[0].timestamp, 1000)
        XCTAssertTrue(nals[0].isAccessUnitEnd)
    }

    func testSTAPAYieldsMultipleNALs() {
        let dep = H264Depacketizer()
        // type 24, [size=2][0x67,0x42], [size=1][0x68]
        let nals = dep.depacketize(packet([24, 0, 2, 0x67, 0x42, 0, 1, 0x68], marker: true))
        XCTAssertEqual(nals.map(\.data), [Data([0x67, 0x42]), Data([0x68])])
        // Only the last aggregated NAL ends the access unit.
        XCTAssertEqual(nals.map(\.isAccessUnitEnd), [false, true])
    }

    func testFUAReassemblyReconstructsNALHeader() {
        let dep = H264Depacketizer()
        // Original IDR header 0x65 → FU indicator 0x7C (F|NRI from 0x65, type 28),
        // FU header start 0x85 / end 0x45 (type 5).
        XCTAssertEqual(dep.depacketize(packet([0x7C, 0x85, 0xAA, 0xBB])).count, 0)  // start, incomplete
        let done = dep.depacketize(packet([0x7C, 0x45, 0xCC, 0xDD], marker: true))   // end
        XCTAssertEqual(done.count, 1)
        XCTAssertEqual(done[0].data, Data([0x65, 0xAA, 0xBB, 0xCC, 0xDD]))
        XCTAssertTrue(done[0].isAccessUnitEnd)
    }

    func testFUAThreeFragments() {
        let dep = H264Depacketizer()
        _ = dep.depacketize(packet([0x7C, 0x85, 0x01]))           // start
        _ = dep.depacketize(packet([0x7C, 0x05, 0x02]))           // middle (S=0,E=0)
        let done = dep.depacketize(packet([0x7C, 0x45, 0x03]))    // end
        XCTAssertEqual(done.first?.data, Data([0x65, 0x01, 0x02, 0x03]))
    }

    func testUnknownTypeDropped() {
        let dep = H264Depacketizer()
        XCTAssertTrue(dep.depacketize(packet([30, 0x00])).isEmpty)  // type 30 unsupported
    }
}

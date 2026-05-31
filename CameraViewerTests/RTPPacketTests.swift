import XCTest
@testable import CameraViewer

final class RTPPacketTests: XCTestCase {
    func testParsesHeaderFieldsBigEndian() {
        // V=2, no padding/ext/csrc; M=1, PT=97; seq=0x1234; ts=0x0A0B0C0D; ssrc=0x11223344
        var bytes: [UInt8] = [0x80, 0x80 | 97, 0x12, 0x34, 0x0A, 0x0B, 0x0C, 0x0D,
                              0x11, 0x22, 0x33, 0x44]
        bytes += [0xDE, 0xAD, 0xBE, 0xEF]   // payload
        let pkt = RTPPacket(Data(bytes))
        XCTAssertNotNil(pkt)
        XCTAssertEqual(pkt?.payloadType, 97)
        XCTAssertTrue(pkt!.marker)
        XCTAssertEqual(pkt?.sequenceNumber, 0x1234)
        XCTAssertEqual(pkt?.timestamp, 0x0A0B0C0D)
        XCTAssertEqual(pkt?.ssrc, 0x11223344)
        XCTAssertEqual(pkt?.payload, Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    func testMarkerBitClear() {
        let bytes: [UInt8] = [0x80, 96, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0xAA]
        XCTAssertEqual(RTPPacket(Data(bytes))?.marker, false)
        XCTAssertEqual(RTPPacket(Data(bytes))?.payloadType, 96)
    }

    func testSkipsCSRCList() {
        // CC=2 → two 4-byte CSRC identifiers between header and payload.
        var bytes: [UInt8] = [0x82, 96, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        bytes += [1, 1, 1, 1, 2, 2, 2, 2]   // 2 CSRCs
        bytes += [0x55]                       // payload
        XCTAssertEqual(RTPPacket(Data(bytes))?.payload, Data([0x55]))
    }

    func testSkipsHeaderExtension() {
        // X=1; extension = 4-byte header (profile + length=1 word) + 1 word (4 bytes).
        var bytes: [UInt8] = [0x90, 96, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        bytes += [0xBE, 0xDE, 0x00, 0x01, 0xAA, 0xBB, 0xCC, 0xDD]  // ext hdr + 1 word
        bytes += [0x99]                                              // payload
        XCTAssertEqual(RTPPacket(Data(bytes))?.payload, Data([0x99]))
    }

    func testRejectsTooShort() {
        XCTAssertNil(RTPPacket(Data([0x80, 96, 0, 0])))
    }

    func testRejectsWrongVersion() {
        // version bits = 0
        XCTAssertNil(RTPPacket(Data([0x00, 96, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])))
    }

    func testEmptyPayloadAllowed() {
        let bytes: [UInt8] = [0x80, 96, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        XCTAssertEqual(RTPPacket(Data(bytes))?.payload.count, 0)
    }
}

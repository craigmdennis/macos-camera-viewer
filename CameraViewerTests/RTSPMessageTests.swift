import XCTest
@testable import CameraViewer

final class RTSPMessageTests: XCTestCase {
    func testRequestSerializesWithCRLFAndBlankLineTerminator() {
        let req = RTSPRequest(method: "DESCRIBE", uri: "rtsp://host/cam", cseq: 1,
                              headers: ["Accept": "application/sdp"])
        let out = req.serialized(userAgent: "CameraViewer")
        XCTAssertTrue(out.hasPrefix("DESCRIBE rtsp://host/cam RTSP/1.0\r\n"))
        XCTAssertTrue(out.contains("\r\nCSeq: 1\r\n"))
        XCTAssertTrue(out.contains("\r\nAccept: application/sdp\r\n"))
        XCTAssertTrue(out.hasSuffix("\r\n\r\n"))
    }

    func testRequestWithBodyAddsContentLength() {
        let req = RTSPRequest(method: "SET_PARAMETER", uri: "rtsp://host/cam", cseq: 5, body: "hi")
        let out = req.serialized()
        XCTAssertTrue(out.contains("\r\nContent-Length: 2\r\n\r\nhi"))
    }

    func testParsesRealUniFi200Response() {
        let raw = "RTSP/1.0 200 OK\r\nCSeq: 1\r\nContent-Base: rtsps://10.0.0.1:7441/tok/\r\n"
            + "Content-Type: application/sdp\r\nSession: 1234ABCD;timeout=60\r\nContent-Length: 5\r\n\r\nv=0\r\n"
        let resp = RTSPResponse.parse(raw)
        XCTAssertNotNil(resp)
        XCTAssertEqual(resp?.statusCode, 200)
        XCTAssertTrue(resp!.isOK)
        XCTAssertEqual(resp?.cseq, 1)
        XCTAssertEqual(resp?.contentBase, "rtsps://10.0.0.1:7441/tok/")
        XCTAssertEqual(resp?.session, "1234ABCD")
        XCTAssertTrue(resp!.body.hasPrefix("v=0"))
    }

    func testParses401() {
        let raw = "RTSP/1.0 401 Unauthorized\r\nCSeq: 2\r\nWWW-Authenticate: Digest realm=\"x\"\r\n\r\n"
        let resp = RTSPResponse.parse(raw)
        XCTAssertEqual(resp?.statusCode, 401)
        XCTAssertFalse(resp?.isOK ?? true)
        XCTAssertEqual(resp?.headers["www-authenticate"], "Digest realm=\"x\"")
    }

    func testRejectsNonRTSPText() {
        XCTAssertNil(RTSPResponse.parse("garbage\r\n\r\n"))
    }
}

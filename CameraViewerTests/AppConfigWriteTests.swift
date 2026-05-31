import XCTest
@testable import CameraViewer

final class AppConfigWriteTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cvtest-\(UUID().uuidString)")
            .appendingPathComponent("config.json")
    }

    func testSaveThenLoadRoundTrips() throws {
        let url = tempURL()
        let config = AppConfig(cameras: [
            CameraConfig(name: "Front Door", uri: URL(string: "rtsps://10.0.0.1:7441/abc?enableSrtp")!),
            CameraConfig(name: "Garden", uri: URL(string: "rtsps://10.0.0.1:7441/def?enableSrtp")!),
        ])
        try AppConfigLoader.save(config, to: url)
        XCTAssertEqual(try AppConfigLoader.load(from: url), config)
    }

    func testSavePreservesCamerasArrayShape() throws {
        let url = tempURL()
        try AppConfigLoader.save(AppConfig(cameras: [
            CameraConfig(name: "X", uri: URL(string: "rtsps://h/1")!),
        ]), to: url)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let cameras = json?["cameras"] as? [[String: Any]]
        XCTAssertEqual(cameras?.count, 1)
        XCTAssertEqual(cameras?.first?["name"] as? String, "X")
        XCTAssertNotNil(cameras?.first?["uri"])
        XCTAssertNil(json?["_comment"])   // real saves are clean, no stub comment
    }

    func testSaveCreatesIntermediateDirectories() throws {
        let url = tempURL()   // parent dir does not exist yet
        XCTAssertNoThrow(try AppConfigLoader.save(AppConfig(cameras: [
            CameraConfig(name: "X", uri: URL(string: "rtsps://h/1")!),
        ]), to: url))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - URL validation

    func testValidRTSPSURL() {
        XCTAssertNotNil(CameraURLValidator.validate("rtsps://10.0.0.1:7441/abc?enableSrtp"))
    }

    func testValidPlainRTSPURL() {
        XCTAssertNotNil(CameraURLValidator.validate("rtsp://10.0.0.1:7447/abc"))
    }

    func testTrimsWhitespace() {
        XCTAssertNotNil(CameraURLValidator.validate("  rtsps://h/abc \n"))
    }

    func testRejectsWrongScheme() {
        XCTAssertNil(CameraURLValidator.validate("http://10.0.0.1/abc"))
    }

    func testRejectsMissingHost() {
        XCTAssertNil(CameraURLValidator.validate("rtsps:///abc"))
    }

    func testRejectsGarbage() {
        XCTAssertNil(CameraURLValidator.validate("not a url"))
        XCTAssertNil(CameraURLValidator.validate(""))
    }
}

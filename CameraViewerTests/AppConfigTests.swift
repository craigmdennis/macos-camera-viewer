import XCTest
@testable import CameraViewer

final class AppConfigTests: XCTestCase {
    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testRoundTripEncodeDecode() throws {
        let original = AppConfig(cameras: [
            CameraConfig(name: "Front Door", uri: URL(string: "rtsps://10.0.0.1:7441/abc?enableSrtp")!)
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testDecodeIgnoresUnknownKeys() throws {
        let json = #"""
        {
          "_comment": "hello",
          "cameras": [
            { "name": "Front Door", "uri": "rtsps://10.0.0.1:7441/abc?enableSrtp" }
          ]
        }
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(decoded.cameras.count, 1)
        XCTAssertEqual(decoded.cameras[0].name, "Front Door")
        XCTAssertEqual(decoded.cameras[0].uri.absoluteString, "rtsps://10.0.0.1:7441/abc?enableSrtp")
    }

    func testLoadThrowsFileNotFoundWhenMissing() {
        let missing = tmpDir.appendingPathComponent("nope.json")
        XCTAssertThrowsError(try AppConfigLoader.load(from: missing)) { error in
            guard case AppConfigError.fileNotFound = error else {
                return XCTFail("expected fileNotFound, got \(error)")
            }
        }
    }

    func testLoadThrowsMalformedOnBadJSON() throws {
        let url = tmpDir.appendingPathComponent("bad.json")
        try "{ not json }".data(using: .utf8)!.write(to: url)
        XCTAssertThrowsError(try AppConfigLoader.load(from: url)) { error in
            guard case AppConfigError.malformed = error else {
                return XCTFail("expected malformed, got \(error)")
            }
        }
    }

    func testLoadThrowsMalformedOnEmptyCamerasArray() throws {
        let url = tmpDir.appendingPathComponent("empty.json")
        try #"{ "cameras": [] }"#.data(using: .utf8)!.write(to: url)
        XCTAssertThrowsError(try AppConfigLoader.load(from: url)) { error in
            guard case AppConfigError.malformed = error else {
                return XCTFail("expected malformed, got \(error)")
            }
        }
    }

    // Old single-URL configs have no "cameras" key — Codable ignores unknown keys,
    // so they decode to cameras:[] and hit the empty-array guard.
    func testLoadThrowsMalformedOnMissingCamerasKey() throws {
        let url = tmpDir.appendingPathComponent("old.json")
        try #"{ "rtspsURL": "rtsps://10.0.0.1:7441/abc?enableSrtp" }"#.data(using: .utf8)!.write(to: url)
        XCTAssertThrowsError(try AppConfigLoader.load(from: url)) { error in
            guard case AppConfigError.malformed = error else {
                return XCTFail("expected malformed, got \(error)")
            }
        }
    }

    func testWriteStubCreatesDirectoryAndValidJSON() throws {
        let url = tmpDir
            .appendingPathComponent("sub", isDirectory: true)
            .appendingPathComponent("config.json")
        try AppConfigLoader.writeStub(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let reloaded = try AppConfigLoader.load(from: url)
        XCTAssertFalse(reloaded.cameras.isEmpty)
        XCTAssertEqual(reloaded.cameras[0].uri.scheme, "rtsps")
    }
}

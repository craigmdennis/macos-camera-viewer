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
        let original = AppConfig(rtspsURL: URL(string: "rtsps://10.0.0.1:7441/abc?enableSrtp")!)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testDecodeIgnoresUnknownKeys() throws {
        let json = #"""
        { "_comment": "hello", "rtspsURL": "rtsps://10.0.0.1:7441/abc?enableSrtp" }
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(decoded.rtspsURL.absoluteString, "rtsps://10.0.0.1:7441/abc?enableSrtp")
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

    func testWriteStubCreatesDirectoryAndValidJSON() throws {
        let url = tmpDir
            .appendingPathComponent("sub", isDirectory: true)
            .appendingPathComponent("config.json")
        try AppConfigLoader.writeStub(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let reloaded = try AppConfigLoader.load(from: url)
        XCTAssertEqual(reloaded.rtspsURL.scheme, "rtsps")
    }
}

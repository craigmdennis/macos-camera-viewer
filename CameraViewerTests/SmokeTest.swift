import XCTest
@testable import CameraViewer

final class SmokeTest: XCTestCase {
    // Touches the app module so the test target links.
    func testModuleLinks() {
        XCTAssertNotNil(NativeCameraPlayer.self)
        XCTAssertNotNil(RTSPClient.self)
    }
}

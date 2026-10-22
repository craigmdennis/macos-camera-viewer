import Network
import XCTest
@testable import CameraViewer

final class RTSPConnectionTests: XCTestCase {
    func testWaitingIsReportedAsFailure() {
        // A refused reconnect lands in .waiting, which only retries on a path change.
        guard case .failed = RTSPConnection.event(for: .waiting(.posix(.ECONNREFUSED))) else {
            return XCTFail("expected .failed")
        }
    }

    func testFailedIsReportedAsFailure() {
        guard case .failed = RTSPConnection.event(for: .failed(.posix(.ECONNRESET))) else {
            return XCTFail("expected .failed")
        }
    }

    func testPreparingIsIgnored() {
        XCTAssertNil(RTSPConnection.event(for: .preparing))
    }
}

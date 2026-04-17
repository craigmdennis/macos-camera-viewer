import XCTest
@testable import CameraViewer

final class ReconnectPolicyTests: XCTestCase {
    func testSequenceStartsAtOneAndCapsAtTen() {
        var policy = ReconnectPolicy()
        let delays = (0..<7).map { _ in policy.recordFailure() }
        XCTAssertEqual(delays, [1, 2, 4, 8, 10, 10, 10])
    }

    func testResetReturnsToStart() {
        var policy = ReconnectPolicy()
        _ = policy.recordFailure()
        _ = policy.recordFailure()
        _ = policy.recordFailure()
        policy.reset()
        XCTAssertEqual(policy.recordFailure(), 1)
    }

    func testConsecutiveFailuresCounter() {
        var policy = ReconnectPolicy()
        XCTAssertEqual(policy.consecutiveFailures, 0)
        _ = policy.recordFailure()
        XCTAssertEqual(policy.consecutiveFailures, 1)
        _ = policy.recordFailure()
        XCTAssertEqual(policy.consecutiveFailures, 2)
        policy.reset()
        XCTAssertEqual(policy.consecutiveFailures, 0)
    }
}

import XCTest
@testable import CameraViewer

final class SpringTests: XCTestCase {
    func testSettlesOnTargetWithOneOvershoot() {
        var p = CGPoint(x: 300, y: 0), v = CGPoint(x: -800, y: 0)
        let target = CGPoint.zero
        var overshot = false
        for _ in 0..<600 {
            (p, v) = Spring.step(position: p, velocity: v, target: target, dt: 1 / 60)
            if p.x < 0 { overshot = true }
            if Spring.settled(position: p, velocity: v, target: target) { break }
        }
        XCTAssertTrue(Spring.settled(position: p, velocity: v, target: target), "did not settle: \\(p) \\(v)")
        XCTAssertTrue(overshot)
    }
}

import XCTest
@testable import CameraViewer

final class CornerSnapTests: XCTestCase {
    // Use a screen visibleFrame of (0,0, 1920,1080) throughout.
    private let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
    private let windowSize = NSSize(width: 480, height: 270)

    private func window(at origin: NSPoint) -> NSRect {
        NSRect(origin: origin, size: windowSize)
    }

    func testSnapsToBottomLeftWhenOriginNearDock() {
        let snapped = CornerSnap.snap(windowFrame: window(at: NSPoint(x: 30, y: 40)), screenVisibleFrame: screen)
        XCTAssertEqual(snapped.origin, NSPoint(x: 8, y: 8))
        XCTAssertEqual(snapped.size, windowSize)
    }

    func testSnapsToBottomRight() {
        let origin = NSPoint(x: screen.maxX - windowSize.width - 30, y: 30)
        let snapped = CornerSnap.snap(windowFrame: window(at: origin), screenVisibleFrame: screen)
        XCTAssertEqual(snapped.origin, NSPoint(x: screen.maxX - windowSize.width - 8, y: 8))
    }

    func testSnapsToTopLeft() {
        let origin = NSPoint(x: 30, y: screen.maxY - windowSize.height - 30)
        let snapped = CornerSnap.snap(windowFrame: window(at: origin), screenVisibleFrame: screen)
        XCTAssertEqual(snapped.origin, NSPoint(x: 8, y: screen.maxY - windowSize.height - 8))
    }

    func testSnapsToTopRight() {
        let origin = NSPoint(x: screen.maxX - windowSize.width - 30, y: screen.maxY - windowSize.height - 30)
        let snapped = CornerSnap.snap(windowFrame: window(at: origin), screenVisibleFrame: screen)
        XCTAssertEqual(snapped.origin,
                       NSPoint(x: screen.maxX - windowSize.width - 8,
                               y: screen.maxY - windowSize.height - 8))
    }

    func testDoesNotSnapWhenCenteredOnScreen() {
        let origin = NSPoint(x: screen.midX - windowSize.width / 2,
                             y: screen.midY - windowSize.height / 2)
        let frame = window(at: origin)
        XCTAssertEqual(CornerSnap.snap(windowFrame: frame, screenVisibleFrame: screen), frame)
    }

    func testDoesNotSnapJustBeyondThreshold() {
        let d: CGFloat = 81 / sqrt(2)
        let frame = window(at: NSPoint(x: 8 + d, y: 8 + d))
        XCTAssertEqual(CornerSnap.snap(windowFrame: frame, screenVisibleFrame: screen), frame)
    }

    func testSnapsExactlyAtThreshold() {
        let d: CGFloat = 80 / sqrt(2)
        let snapped = CornerSnap.snap(windowFrame: window(at: NSPoint(x: 8 + d, y: 8 + d)), screenVisibleFrame: screen)
        XCTAssertEqual(snapped.origin, NSPoint(x: 8, y: 8))
    }

    func testFlickTowardCornerDocksThere() {
        // 300 px from the dock, released with a 2000 pt/s flick toward it (projects 500 px).
        let frame = window(at: NSPoint(x: 308, y: 8))
        let target = CornerSnap.flickTarget(windowFrame: frame, velocity: CGPoint(x: -2000, y: 0), screenVisibleFrame: screen)
        XCTAssertEqual(target?.origin, NSPoint(x: 8, y: 8))
    }

    func testReleaseAwayFromCornersReturnsNil() {
        let frame = window(at: NSPoint(x: 600, y: 400))
        XCTAssertNil(CornerSnap.flickTarget(windowFrame: frame, velocity: .zero, screenVisibleFrame: screen))
    }
}

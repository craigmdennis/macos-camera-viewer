import XCTest
@testable import CameraViewer

final class CornerSnapTests: XCTestCase {
    // Use a screen visibleFrame of (0,0, 1920,1080) throughout.
    private let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
    private let windowSize = NSSize(width: 480, height: 270)

    private func window(at origin: NSPoint) -> NSRect {
        NSRect(origin: origin, size: windowSize)
    }

    func testSnapsToBottomLeftWhenCenterNearCorner() {
        // Window center a few px from bottom-left corner
        let originNearBL = NSPoint(x: -windowSize.width / 2 + 10, y: -windowSize.height / 2 + 10)
        let snapped = CornerSnap.snap(windowFrame: window(at: originNearBL), screenVisibleFrame: screen)
        XCTAssertEqual(snapped.origin, NSPoint(x: 8, y: 8))
        XCTAssertEqual(snapped.size, windowSize)
    }

    func testSnapsToBottomRight() {
        let origin = NSPoint(x: screen.maxX - windowSize.width / 2 - 10,
                             y: -windowSize.height / 2 + 10)
        let snapped = CornerSnap.snap(windowFrame: window(at: origin), screenVisibleFrame: screen)
        XCTAssertEqual(snapped.origin, NSPoint(x: screen.maxX - windowSize.width - 8, y: 8))
    }

    func testSnapsToTopLeft() {
        let origin = NSPoint(x: -windowSize.width / 2 + 10,
                             y: screen.maxY - windowSize.height / 2 - 10)
        let snapped = CornerSnap.snap(windowFrame: window(at: origin), screenVisibleFrame: screen)
        XCTAssertEqual(snapped.origin, NSPoint(x: 8, y: screen.maxY - windowSize.height - 8))
    }

    func testSnapsToTopRight() {
        let origin = NSPoint(x: screen.maxX - windowSize.width / 2 - 10,
                             y: screen.maxY - windowSize.height / 2 - 10)
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
        // Center is exactly 81 px from bottom-left corner — outside default threshold of 80.
        let dx: CGFloat = 81 / sqrt(2)
        let origin = NSPoint(x: dx - windowSize.width / 2, y: dx - windowSize.height / 2)
        let frame = window(at: origin)
        XCTAssertEqual(CornerSnap.snap(windowFrame: frame, screenVisibleFrame: screen), frame)
    }

    func testSnapsExactlyAtThreshold() {
        let dx: CGFloat = 80 / sqrt(2)
        let origin = NSPoint(x: dx - windowSize.width / 2, y: dx - windowSize.height / 2)
        let snapped = CornerSnap.snap(windowFrame: window(at: origin), screenVisibleFrame: screen)
        XCTAssertEqual(snapped.origin, NSPoint(x: 8, y: 8))
    }
}

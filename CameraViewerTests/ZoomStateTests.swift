import XCTest
@testable import CameraViewer

final class ZoomStateTests: XCTestCase {
    private let viewSize = CGSize(width: 400, height: 300)
    private let center = CGPoint(x: 200, y: 150)

    // Screen mapping the transform realises: screen = scale·p + translation.
    private func screen(_ p: CGPoint, _ s: ZoomState) -> CGPoint {
        CGPoint(x: s.scale * p.x + s.translation.x, y: s.scale * p.y + s.translation.y)
    }

    func testInitialStateIsIdentity() {
        let state = ZoomState()
        XCTAssertEqual(state.scale, 1.0)
        XCTAssertEqual(state.translation, .zero)
        XCTAssertFalse(state.isZoomed)
    }

    func testScaleMultipliesAndClamps() {
        var state = ZoomState()
        state.applyScaleDelta(2.0, focus: center, viewSize: viewSize)
        XCTAssertEqual(state.scale, 2.0, accuracy: 0.0001)
        XCTAssertTrue(state.isZoomed)

        state.applyScaleDelta(100, focus: center, viewSize: viewSize)
        XCTAssertEqual(state.scale, 8.0, accuracy: 0.0001)

        state.applyScaleDelta(0.0001, focus: center, viewSize: viewSize)
        XCTAssertEqual(state.scale, 1.0, accuracy: 0.0001)
        XCTAssertFalse(state.isZoomed)
    }

    func testZoomingAtCenterCentresContent() {
        var state = ZoomState()
        state.applyScaleDelta(2.0, focus: center, viewSize: viewSize)
        // Center fixed → translation pulls back by (scale-1)·center.
        XCTAssertEqual(state.translation.x, -200, accuracy: 0.0001)
        XCTAssertEqual(state.translation.y, -150, accuracy: 0.0001)
    }

    func testZoomingAtCornerKeepsCornerFixed() {
        var state = ZoomState()
        state.applyScaleDelta(2.0, focus: .zero, viewSize: viewSize)
        XCTAssertEqual(state.translation, .zero)
    }

    func testFocusPointStaysUnderCursor() {
        var state = ZoomState()
        state.applyScaleDelta(2.0, focus: center, viewSize: viewSize)
        let focus = CGPoint(x: 100, y: 75)
        state.applyScaleDelta(1.5, focus: focus, viewSize: viewSize)
        XCTAssertEqual(state.scale, 3.0, accuracy: 0.0001)
        // The point under the cursor must not move on screen.
        let mapped = screen(CGPoint(x: 150, y: 112.5), state) // content pt that was at `focus`
        XCTAssertEqual(mapped.x, focus.x, accuracy: 0.0001)
        XCTAssertEqual(mapped.y, focus.y, accuracy: 0.0001)
    }

    // The defining guarantee: scaled content always covers the view (no black bars).
    func testContentAlwaysCoversViewAfterZoom() {
        var state = ZoomState()
        state.applyScaleDelta(2.0, focus: CGPoint(x: 5000, y: 5000), viewSize: viewSize)
        assertCovers(state)
    }

    func testPanGrabsContentAndStaysCovering() {
        var state = ZoomState()
        state.applyScaleDelta(2.0, focus: center, viewSize: viewSize) // translation (-200,-150)
        state.applyPanDelta(CGPoint(x: 100, y: 50), viewSize: viewSize)
        XCTAssertEqual(state.translation.x, -100, accuracy: 0.0001)
        XCTAssertEqual(state.translation.y, -100, accuracy: 0.0001)
        assertCovers(state)
    }

    func testPanClampsToCoveringRange() {
        var state = ZoomState()
        state.applyScaleDelta(2.0, focus: center, viewSize: viewSize)

        state.applyPanDelta(CGPoint(x: 10_000, y: 10_000), viewSize: viewSize)
        XCTAssertEqual(state.translation, .zero) // can't expose top/left edge
        assertCovers(state)

        state.applyPanDelta(CGPoint(x: -100_000, y: -100_000), viewSize: viewSize)
        XCTAssertEqual(state.translation.x, -400, accuracy: 0.0001) // -(2-1)·400
        XCTAssertEqual(state.translation.y, -300, accuracy: 0.0001)
        assertCovers(state)
    }

    func testZoomingBackToOneReclampsToZero() {
        var state = ZoomState()
        state.applyScaleDelta(4.0, focus: center, viewSize: viewSize)
        state.applyPanDelta(CGPoint(x: -1000, y: -1000), viewSize: viewSize)
        state.applyScaleDelta(0.0001, focus: center, viewSize: viewSize)
        XCTAssertEqual(state.scale, 1.0, accuracy: 0.0001)
        XCTAssertEqual(state.translation, .zero)
    }

    func testReclampAfterViewShrinks() {
        var state = ZoomState()
        state.applyScaleDelta(2.0, focus: center, viewSize: viewSize)
        state.applyPanDelta(CGPoint(x: -10_000, y: -10_000), viewSize: viewSize) // (-400,-300)
        let smaller = CGSize(width: 200, height: 150)
        state.reclamp(viewSize: smaller)
        XCTAssertEqual(state.translation.x, -200, accuracy: 0.0001) // -(2-1)·200
        XCTAssertEqual(state.translation.y, -150, accuracy: 0.0001)
    }

    func testRestoreSetsValuesAndClamps() {
        var state = ZoomState()
        state.restore(scale: 3.0, translation: CGPoint(x: -100, y: -10_000), viewSize: viewSize)
        XCTAssertEqual(state.scale, 3.0, accuracy: 0.0001)
        XCTAssertEqual(state.translation.x, -100, accuracy: 0.0001)
        XCTAssertEqual(state.translation.y, -600, accuracy: 0.0001) // clamped to -(3-1)·300
        XCTAssertTrue(state.isZoomed)
        assertCovers(state)
    }

    func testRestoreClampsScaleToRange() {
        var state = ZoomState()
        state.restore(scale: 100, translation: .zero, viewSize: viewSize)
        XCTAssertEqual(state.scale, 8.0, accuracy: 0.0001)
    }

    func testResetReturnsToIdentity() {
        var state = ZoomState()
        state.applyScaleDelta(3.0, focus: center, viewSize: viewSize)
        state.applyPanDelta(CGPoint(x: -30, y: -30), viewSize: viewSize)
        state.reset()
        XCTAssertEqual(state.scale, 1.0)
        XCTAssertEqual(state.translation, .zero)
        XCTAssertFalse(state.isZoomed)
    }

    // Content spans [translation, scale·dim + translation]; it must cover [0, dim].
    private func assertCovers(_ s: ZoomState, file: StaticString = #file, line: UInt = #line) {
        XCTAssertLessThanOrEqual(s.translation.x, 0.0001, "left edge exposed", file: file, line: line)
        XCTAssertLessThanOrEqual(s.translation.y, 0.0001, "bottom edge exposed", file: file, line: line)
        XCTAssertGreaterThanOrEqual(s.scale * viewSize.width + s.translation.x, viewSize.width - 0.0001,
                                    "right edge exposed", file: file, line: line)
        XCTAssertGreaterThanOrEqual(s.scale * viewSize.height + s.translation.y, viewSize.height - 0.0001,
                                    "top edge exposed", file: file, line: line)
    }
}

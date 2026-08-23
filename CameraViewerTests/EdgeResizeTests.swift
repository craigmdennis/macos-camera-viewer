import XCTest
@testable import CameraViewer

final class EdgeResizeTests: XCTestCase {
    private let start = NSRect(x: 100, y: 100, width: 480, height: 270)
    private let minSize = CGSize(width: 320, height: 180)
    private let maxSize = CGSize(width: 1600, height: 900)

    func testEdgeDetectionInFlippedCoords() {
        let size = CGSize(width: 480, height: 270)
        XCTAssertEqual(EdgeResize.edges(at: CGPoint(x: 5, y: 5), in: size), [.top, .left])
        XCTAssertEqual(EdgeResize.edges(at: CGPoint(x: 475, y: 265), in: size), [.bottom, .right])
        XCTAssertEqual(EdgeResize.edges(at: CGPoint(x: 240, y: 265), in: size), .bottom)
        XCTAssertEqual(EdgeResize.edges(at: CGPoint(x: 240, y: 135), in: size), [])
    }

    func testRightEdgeGrowsWidthKeepingLeftFixed() {
        let f = EdgeResize.frame(start: start, edges: .right, delta: CGPoint(x: 40, y: 0),
                                 aspect: nil, min: minSize, max: maxSize)
        XCTAssertEqual(f, NSRect(x: 100, y: 100, width: 520, height: 270))
    }

    func testLeftEdgeKeepsRightFixed() {
        let f = EdgeResize.frame(start: start, edges: .left, delta: CGPoint(x: -40, y: 0),
                                 aspect: nil, min: minSize, max: maxSize)
        XCTAssertEqual(f.maxX, start.maxX)
        XCTAssertEqual(f.width, 520)
    }

    func testBottomEdgeKeepsTopFixed() {
        let f = EdgeResize.frame(start: start, edges: .bottom, delta: CGPoint(x: 0, y: -30),
                                 aspect: nil, min: minSize, max: maxSize)
        XCTAssertEqual(f.maxY, start.maxY)
        XCTAssertEqual(f.height, 300)
    }

    func testAspectRatioDerivesHeightFromWidthOnCornerDrag() {
        let f = EdgeResize.frame(start: start, edges: [.bottom, .right], delta: CGPoint(x: 160, y: 0),
                                 aspect: CGSize(width: 16, height: 9), min: minSize, max: maxSize)
        XCTAssertEqual(f.width, 640)
        XCTAssertEqual(f.height, 360)
        XCTAssertEqual(f.maxY, start.maxY)
    }

    func testClampsToMinAndPreservesAspect() {
        let f = EdgeResize.frame(start: start, edges: .right, delta: CGPoint(x: -400, y: 0),
                                 aspect: CGSize(width: 16, height: 9), min: minSize, max: maxSize)
        XCTAssertEqual(f.width, 320)
        XCTAssertEqual(f.height, 180)
    }
}

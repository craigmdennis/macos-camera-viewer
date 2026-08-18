import XCTest
@testable import CameraViewer

final class PiPLayoutTests: XCTestCase {
    func testTileCount() {
        XCTAssertEqual(PiPLayout.single.tileCount, 1)
        XCTAssertEqual(PiPLayout.split2.tileCount, 2)
        XCTAssertEqual(PiPLayout.grid4.tileCount, 4)
    }

    func testFramesCountMatchesTileCount() {
        let size = CGSize(width: 400, height: 300)
        for layout in PiPLayout.allCases {
            let frames = PiPLayout.frames(for: layout, containerSize: size, spacing: 2)
            XCTAssertEqual(frames.count, layout.tileCount, "\(layout)")
        }
    }

    func testSingleFillsContainer() {
        let size = CGSize(width: 400, height: 300)
        let frames = PiPLayout.frames(for: .single, containerSize: size, spacing: 2)
        XCTAssertEqual(frames, [CGRect(origin: .zero, size: size)])
    }

    func testSplit2StacksWithoutOverlap() {
        let size = CGSize(width: 400, height: 300)
        let frames = PiPLayout.frames(for: .split2, containerSize: size, spacing: 4)
        XCTAssertEqual(frames.count, 2)
        XCTAssertFalse(frames[0].intersects(frames[1]))
        for frame in frames {
            XCTAssertEqual(frame.width, size.width)
        }
        // Together with the spacing gap, the two tiles span the full container height.
        let totalHeight = frames.reduce(0) { $0 + $1.height } + 4
        XCTAssertEqual(totalHeight, size.height, accuracy: 0.01)
    }

    func testGrid4TilesWithoutOverlap() {
        let size = CGSize(width: 400, height: 300)
        let frames = PiPLayout.frames(for: .grid4, containerSize: size, spacing: 2)
        XCTAssertEqual(frames.count, 4)
        for i in 0..<frames.count {
            for j in (i + 1)..<frames.count where j != i {
                XCTAssertFalse(frames[i].intersects(frames[j]), "\(i) vs \(j)")
            }
        }
        let totalArea = frames.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
        let expectedArea = size.width * size.height
            - size.width * 2       // horizontal spacing strip
            - size.height * 2      // vertical spacing strip
            + 2 * 2                // spacing strips overlap once at the center
        XCTAssertEqual(totalArea, expectedArea, accuracy: 0.01)
    }

    func testMinWindowSizeIsPositive() {
        // Live-resize is aspect-locked once a camera's video size is known (see
        // PiPWindowController.lockAspectRatio), so contentMinSize only needs to be a
        // small floor against a degenerate window — it isn't expected to scale with
        // tile count.
        for layout in PiPLayout.allCases {
            XCTAssertGreaterThan(layout.minWindowSize.width, 0, "\(layout)")
            XCTAssertGreaterThan(layout.minWindowSize.height, 0, "\(layout)")
        }
    }
}

import XCTest
import AppKit
@testable import CameraViewer

final class PersistenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PersistenceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testLoadFrameReturnsNilWhenUnset() {
        let p = Persistence(defaults: defaults)
        XCTAssertNil(p.loadFrame())
    }

    func testRoundTripFrame() {
        let p = Persistence(defaults: defaults)
        let rect = NSRect(x: 100, y: 200, width: 640, height: 360)
        p.saveFrame(rect)
        XCTAssertEqual(p.loadFrame(), rect)
    }

    func testLoadMutedDefaultsToTrueWhenUnset() {
        let p = Persistence(defaults: defaults)
        XCTAssertTrue(p.loadMuted(), "first launch should default to muted")
    }

    func testRoundTripMuted() {
        let p = Persistence(defaults: defaults)
        p.saveMuted(false)
        XCTAssertFalse(p.loadMuted())
        p.saveMuted(true)
        XCTAssertTrue(p.loadMuted())
    }

    func testLoadSelectedCameraNameReturnsNilWhenUnset() {
        let p = Persistence(defaults: defaults)
        XCTAssertNil(p.loadSelectedCameraName())
    }

    func testRoundTripSelectedCameraName() {
        let p = Persistence(defaults: defaults)
        p.saveSelectedCameraName("Front Door")
        XCTAssertEqual(p.loadSelectedCameraName(), "Front Door")
        p.saveSelectedCameraName("Back Yard")
        XCTAssertEqual(p.loadSelectedCameraName(), "Back Yard")
    }

    func testLoadZoomReturnsNilWhenUnset() {
        let p = Persistence(defaults: defaults)
        XCTAssertNil(p.loadZoom(camera: "Front Door"))
    }

    func testRoundTripZoomPerCamera() {
        let p = Persistence(defaults: defaults)
        p.saveZoom(camera: "Front Door", scale: 2.5, translation: CGPoint(x: -120, y: -80))
        let loaded = p.loadZoom(camera: "Front Door")
        XCTAssertEqual(loaded?.scale ?? 0, 2.5, accuracy: 0.0001)
        XCTAssertEqual(loaded?.translation.x ?? 0, -120, accuracy: 0.0001)
        XCTAssertEqual(loaded?.translation.y ?? 0, -80, accuracy: 0.0001)
    }

    func testZoomIsolatedBetweenCameras() {
        let p = Persistence(defaults: defaults)
        p.saveZoom(camera: "A", scale: 2.0, translation: CGPoint(x: -5, y: -5))
        XCTAssertNil(p.loadZoom(camera: "B"))
        XCTAssertEqual(p.loadZoom(camera: "A")?.scale ?? 0, 2.0, accuracy: 0.0001)
    }
}

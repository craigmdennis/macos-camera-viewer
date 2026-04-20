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
}

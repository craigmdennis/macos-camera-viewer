import XCTest
@testable import CameraViewer

final class AudioSpecificConfigTests: XCTestCase {
    // Real fmtp config values captured from the cameras.
    func testParses48kHzMono() {
        // config=1188 → AAC-LC, 48000 Hz, 1 channel (Back Door / Front Door / Garden).
        let asc = AudioSpecificConfig(hex: "1188")
        XCTAssertNotNil(asc)
        XCTAssertEqual(asc?.sampleRate, 48000)
        XCTAssertEqual(asc?.channels, 1)
        XCTAssertEqual([UInt8](asc!.bytes), [0x11, 0x88])
    }

    func testParses16kHzMono() {
        // config=1408 → AAC-LC, 16000 Hz, 1 channel (Ellie's Room).
        let asc = AudioSpecificConfig(hex: "1408")
        XCTAssertEqual(asc?.sampleRate, 16000)
        XCTAssertEqual(asc?.channels, 1)
    }

    func testParsesStereo() {
        // Construct AAC-LC 44100 (index 4) stereo (ch 2): AOT=2, idx=4, ch=2
        // bits: 00010 0100 0010 0000 → 0x12 0x10
        let asc = AudioSpecificConfig(hex: "1210")
        XCTAssertEqual(asc?.sampleRate, 44100)
        XCTAssertEqual(asc?.channels, 2)
    }

    func testRejectsOddLengthHex() {
        XCTAssertNil(AudioSpecificConfig(hex: "118"))
    }

    func testRejectsNonHex() {
        XCTAssertNil(AudioSpecificConfig(hex: "zzzz"))
    }

    func testRejectsTooShort() {
        XCTAssertNil(AudioSpecificConfig(hex: "11"))
    }
}

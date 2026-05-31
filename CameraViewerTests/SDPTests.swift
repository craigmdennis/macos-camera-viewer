import XCTest
@testable import CameraViewer

final class SDPTests: XCTestCase {
    // Real DESCRIBE body captured from a UniFi camera (no ?enableSrtp → no a=crypto).
    private let backDoorSDP = """
    v=0
    o=- 41927 0 IN IP4 10.0.0.1
    s=68D79AE2BA33_0
    u=www.ui.com
    e=info@ui.com
    c=IN IP4 10.0.0.1
    t=0 0
    a=recvonly
    a=control:*
    a=range:npt=now-
    m=audio 0 RTP/AVP 96
    a=recvonly
    a=rtpmap:96 mpeg4-generic/48000/1
    a=control:trackID=0
    a=fmtp:96 streamtype=5; profile-level-id=15; mode=AAC-hbr; config=1188; SizeLength=13; IndexLength=3; IndexDeltaLength=3;
    m=audio 0 RTP/AVP 96
    a=recvonly
    a=rtpmap:96 opus/48000/2
    a=control:trackID=1
    m=video 0 RTP/AVP 97
    a=recvonly
    a=control:trackID=2
    a=rtpmap:97 H264/90000
    a=fmtp:97 profile-level-id=4d4028; packetization-mode=1; sprop-parameter-sets=Z01AKI2NQDIBL/4C3AQEBQAAAwPoAADqYJ2giEag,aO44gA==
    """

    func testParsesAllThreeMediaSectionsInOrder() {
        let info = SDPParser.parse(backDoorSDP)
        XCTAssertEqual(info.media.count, 3)
        XCTAssertEqual(info.media.map(\.kind), [.audio, .audio, .video])
    }

    func testVideoTrackIsH264WithControlAndClock() {
        let video = SDPParser.parse(backDoorSDP).video
        XCTAssertNotNil(video)
        XCTAssertTrue(video!.isH264)
        XCTAssertEqual(video!.clockRate, 90000)
        XCTAssertEqual(video!.control, "trackID=2")
        XCTAssertEqual(video!.payloadType, 97)
    }

    func testVideoParameterSetsDecodeToTwoNALUnits() {
        // sprop-parameter-sets has two comma-separated base64 NALs (SPS, PPS).
        let video = SDPParser.parse(backDoorSDP).video
        XCTAssertEqual(video?.parameterSets.count, 2)
        // First NAL's type (lower 5 bits of byte 0) should be 7 (SPS) for H.264.
        let sps = video!.parameterSets[0]
        XCTAssertEqual(sps.first! & 0x1f, 7)
    }

    func testAudioSelectionPrefersAACOverOpus() {
        let audio = SDPParser.parse(backDoorSDP).audio
        XCTAssertNotNil(audio)
        XCTAssertTrue(audio!.isAAC)
        XCTAssertEqual(audio!.control, "trackID=0")
        XCTAssertEqual(audio!.clockRate, 48000)
        XCTAssertEqual(audio!.channels, 1)
        XCTAssertEqual(audio!.fmtp["config"], "1188")
        XCTAssertEqual(audio!.fmtp["mode"], "AAC-hbr")
    }

    func testBothAudioSectionsShareSamePayloadTypeButDistinctEncodings() {
        // Regression: PT is per-section, not a global key.
        let audios = SDPParser.parse(backDoorSDP).media.filter { $0.kind == .audio }
        XCTAssertEqual(audios.map(\.payloadType), [96, 96])
        XCTAssertEqual(audios.map { $0.encoding.lowercased() }, ["mpeg4-generic", "opus"])
    }

    func testCryptoAbsentWithoutEnableSrtp() {
        XCTAssertFalse(SDPParser.parse(backDoorSDP).media.contains { $0.hasCrypto })
    }

    func testCryptoDetectedWhenPresent() {
        let withCrypto = backDoorSDP + "\na=crypto:1 AES_CM_128_HMAC_SHA1_80 inline:abc"
        // The crypto line attaches to the last media section (video).
        XCTAssertTrue(SDPParser.parse(withCrypto).video!.hasCrypto)
    }

    // Real RTSP uses CRLF line endings. Swift treats "\r\n" as ONE Character (grapheme
    // cluster), so a naive split on "\r"/"\n" Characters fails to break lines. This test
    // replicates the wire format the camera actually sends.
    func testParsesCRLFLineEndings() {
        let crlf = backDoorSDP.replacingOccurrences(of: "\n", with: "\r\n")
        let info = SDPParser.parse(crlf)
        XCTAssertEqual(info.media.count, 3, "CRLF SDP must split into 3 media sections")
        XCTAssertTrue(info.video?.isH264 ?? false)
        XCTAssertEqual(info.video?.control, "trackID=2")
        XCTAssertEqual(info.video?.parameterSets.count, 2)
        XCTAssertTrue(info.audio?.isAAC ?? false)
    }
}

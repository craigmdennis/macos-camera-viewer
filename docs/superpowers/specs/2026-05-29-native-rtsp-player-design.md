# Native RTSP Player Design (Purist / "3b")

**Date:** 2026-05-29 (capture confirmed 2026-05-30)
**Status:** Draft — **stream capture complete**; key facts confirmed against the live
cameras (see *Confirmed by capture*). **Headline correction vs. earlier drafts: the
cameras stream H.264, not HEVC.** Ready for implementation.

## Overview

Replace the entire media stack — **VLCKit, the bundled `ffmpeg` transcode, and the
`go2rtc` subprocess** — with a fully native, single-process pipeline built only on
Apple frameworks plus permissively-licensed (MIT/Apache/BSD) helper code:

```
rtsps:// (TLS, Network.framework)
   → RTSP/1.0 control state machine (hand-written)
   → RTP over TCP-interleaved channel (no SRTP — TLS already encrypts)
   → H.264 / H.265 depacketizer (RFC 6184 / RFC 7798; cameras are H.264 — primary path)
   → VideoToolbox decode via AVSampleBufferDisplayLayer
   → (AAC audio, RFC 3640 → AVSampleBufferAudioRenderer)
```

### Why

- **Performance:** one process, hardware decode (VideoToolbox), hardware AES (TLS),
  no transcode, no IPC, no loopback hop, and full control of jitter buffering →
  lowest CPU/memory/latency of any option evaluated. See research summary in the
  session notes; resource ranking is fully-native < go2rtc-passthrough < current.
- **Dependency hygiene:** removes the two licensing-problem dependencies (LGPL
  VLCKit, GPL ffmpeg) and the subprocess. Runtime third-party code becomes zero;
  any vendored depacketizer source is MIT/Apache.
- **Capability we gain:** exact `videoSize` from the SPS immediately (no async
  polling), and a path that is sandbox/App-Store-compatible later if desired.

### Why this is feasible (the SRTP non-problem) — confirmed by capture

UniFi's `rtsps://…:7441` is **RTSP-over-TLS with TCP-interleaved media** — the media
is already encrypted by the TLS tunnel. **Capture confirmed the exact behaviour:**
`?enableSrtp` is purely a crypto toggle — with it, the DESCRIBE SDP carries an SDES
`a=crypto:1 AES_CM_128_HMAC_SHA1_80 inline:…` line on every track; **without it, the SDP
is byte-for-byte identical minus the crypto lines** (same codecs, same tracks, plain RTP).
**So we strip `?enableSrtp` from the configured URL and get plain RTP inside the TLS
tunnel — no SRTP to implement.** The self-signed NVR certificate (no IP SAN) is accepted
without verification, exactly as go2rtc's `rtspx://` scheme does.

## Non-goals

- No change to the menu-bar, window, corner-snap, hover-chrome, or persistence behaviour.
- No SRTP, no UDP transport, no plain-RTSP-on-7447 in the shipping path (7447 is a
  debugging aid only).
- No re-architecture of zoom/pan — it ports unchanged (see below).

## What ports unchanged

- **Zoom/pan.** `ZoomController` applies a `CATransform3D` to a backing `CALayer`
  (`view.layer.transform`). `AVSampleBufferDisplayLayer` **is** a `CALayer` subclass,
  so the transform composes exactly as before. The new player view's backing layer is
  the display layer; `ZoomController(view:)` is constructed the same way.
- **`DrawableView`'s `hitTest → nil`** trick (sibling `HoverTrackingView` owns events)
  is retained on the new view.
- **`PiPWindowController`** reconnect loop, aspect-ratio lock, hover, persistence, and
  the `@Published`/Combine wiring are unchanged — they depend only on the player's
  public surface, which we preserve (below). `scheduleVideoSizeLock`'s polling timer is
  removed because `videoSize` is known synchronously after DESCRIBE/first SPS.

## Player surface (drop-in replacement for `CameraPlayer`)

`NativeCameraPlayer` reproduces the exact surface `PiPWindowController` consumes today:

```swift
@Published private(set) var state: State          // .idle/.opening/.playing/.buffering/.error
@Published private(set) var isMuted: Bool
var videoSize: CGSize? { get }                    // from SPS, available after handshake
init(view: SampleBufferView, initiallyMuted: Bool)
func play(url: URL)
func stop()
func setMuted(_ muted: Bool)
```

State mapping: `.opening` = TLS+RTSP handshake; `.buffering` = connected, awaiting first
keyframe; `.playing` = first frame enqueued / frames flowing; `.error` = connection drop,
auth failure, or decode failure (drives the existing `ReconnectPolicy`). `.ended/.stopped`
collapse to `.error` so the existing reconnect picks them up, matching current behaviour.

## Architecture

Files stay under ~150 lines; **pure** parsing/protocol logic is unit-tested, the
NWConnection/VideoToolbox I/O glue is not (per project conventions).

### New files — transport & control

**`CameraViewer/Player/RTSP/RTSPConnection.swift`** *(I/O, not unit-tested)*
Owns an `NWConnection` with a TLS-enabled `NWParameters` that **disables certificate
verification** (self-signed NVR). Provides async send of raw RTSP requests and a receive
loop that demultiplexes the interleaved stream: RTSP responses vs. `$`-framed binary RTP
(RFC 2326 §10.12 — `$`, 1-byte channel, 2-byte big-endian length, payload). Emits parsed
RTSP responses to `RTSPClient` and raw RTP packets to the depacketizers by channel.

**`CameraViewer/Player/RTSP/RTSPClient.swift`** *(orchestration, not unit-tested)*
Drives the control state machine: `OPTIONS → DESCRIBE → SETUP (per track, interleaved)
→ PLAY`, periodic keepalive (`GET_PARAMETER` or `OPTIONS`), and `TEARDOWN` on stop.
Surfaces lifecycle as the player `State`. (No auth needed per capture; a `401`→digest
retry path can be added later if a camera ever requires it.)

**`CameraViewer/Player/RTSP/RTSPMessage.swift`** *(pure, unit-tested)*
Encode requests (method, URL, CSeq, headers) and parse responses (status, headers, body).

**`CameraViewer/Player/RTSP/SDP.swift`** *(pure, unit-tested)*
Parse the DESCRIBE body: media sections, `a=control` track URLs, `rtpmap`/payload types,
`fmtp` parameter sets (`sprop-vps`/`sprop-sps`/`sprop-pps` for HEVC,
`sprop-parameter-sets` for H.264), and audio config. Tolerant of the known empty
secondary Opus track.

**`CameraViewer/Player/RTSP/DigestAuth.swift`** *(deferred — not in v1)*
RFC 7616/2069 digest response computation. **Capture confirmed no auth is required**
(`200 OK` with the URL token on every camera), so this is omitted from v1; add only if a
camera ever returns `401`.

### New files — RTP & depacketization

**`CameraViewer/Player/RTP/RTPPacket.swift`** *(pure, unit-tested)*
Parse the RTP header (version, marker, payload type, sequence, timestamp, SSRC, CSRC,
extension) and expose the payload slice. 16-bit sequence + rollover counter (ROC) tracked
for reordering/loss detection. (No decryption — TLS handles confidentiality.)

**`CameraViewer/Player/RTP/H265Depacketizer.swift`** *(pure, unit-tested)*
RFC 7798: single-NAL, Aggregation (AP, type 48), Fragmentation (FU, type 49). Reassembles
into complete NAL units; separates VPS/SPS/PPS (parameter sets) from VCL NALs; emits access
units keyed by RTP timestamp. Output is raw NALs (start codes stripped). **Secondary/
defensive path — no captured camera used HEVC.**

**`CameraViewer/Player/RTP/H264Depacketizer.swift`** *(pure, unit-tested)*
RFC 6184: single-NAL, STAP-A, FU-A. Same contract as the HEVC depacketizer. **Primary path
— all captured cameras are H.264.**

**`CameraViewer/Player/RTP/AACDepacketizer.swift`** *(pure, unit-tested)*
RFC 3640 `mpeg4-generic` AU-header parsing → raw AAC access units. Only built if audio is
in scope for v1 (see *Phasing*).

### New files — decode & display

**`CameraViewer/Player/Decode/VideoDecoder.swift`** *(I/O, not unit-tested)*
Builds and caches a `CMVideoFormatDescription` via
`CMVideoFormatDescriptionCreateFromH264ParameterSets` (SPS+PPS, `nalUnitHeaderLength = 4`)
— the cameras are H.264 — with `…CreateFromHEVCParameterSets` (VPS+SPS+PPS) as the
defensive fallback. Per access unit: convert NALs to 4-byte
big-endian length-prefixed form, wrap in a `CMBlockBuffer` → `CMSampleBuffer` with
`CMSampleTimingInfo` (PTS from the 90 kHz RTP clock), set
`kCMSampleAttachmentKey_DisplayImmediately`, and enqueue on the display layer's
`sampleBufferRenderer`. Rebuilds the format description only when parameter sets change.
Observes layer `status`; on `.failed` flushes and re-enqueues parameter sets.

**`CameraViewer/Player/Decode/AudioRenderer.swift`** *(I/O, not unit-tested)*
AAC access units → `CMAudioFormatDescription` (from AudioSpecificConfig) → `CMSampleBuffer`
→ `AVSampleBufferAudioRenderer`, synchronised to video via `AVSampleBufferRenderSynchronizer`.
Mute = `renderer.isMuted`. (Phase 2.)

**`CameraViewer/Player/SampleBufferView.swift`** *(I/O, not unit-tested)*
`NSView` whose `makeBackingLayer()` returns an `AVSampleBufferDisplayLayer`
(`videoGravity = .resizeAspect`; window already locks aspect ratio). `hitTest → nil`,
mirroring `DrawableView`. This is the `view` passed to both `NativeCameraPlayer` and
`ZoomController`.

**`CameraViewer/Player/NativeCameraPlayer.swift`** *(orchestration, not unit-tested)*
Wires `RTSPConnection`/`RTSPClient` → depacketizer (selected by SDP codec) →
`VideoDecoder`/`AudioRenderer`. Publishes `state`/`isMuted`, exposes `videoSize`,
implements `play/stop/setMuted`. The drop-in for `CameraPlayer`.

### Modified files

**`CameraViewer/Window/PiPWindowController.swift`**
- Construct `SampleBufferView` instead of `DrawableView`; pass it to
  `NativeCameraPlayer(view:initiallyMuted:)` and `ZoomController(view:)`.
- Strip `?enableSrtp` from the URL before `play` (or do it in the player).
- Remove `scheduleVideoSizeLock` polling; call `applyAspectRatio(player.videoSize)` once
  `.playing`/after DESCRIBE.
- Everything else (reconnect, hover, zoom, persistence) unchanged.

**`CameraViewer/AppDelegate.swift`**
- Remove `StreamProxy` construction/start/stop and the proxy-restart-on-camera-switch
  path; `updateStreamURL` now points the native player straight at the camera URL.

**`project.yml`**
- Remove the `VLCKit.xcframework` dependency and the `bin/go2rtc` resource buildPhase.
- Drop entitlements no longer needed: `com.apple.security.cs.disable-library-validation`
  and (pending audit) `com.apple.security.cs.allow-dyld-environment-variables` — both
  existed only for VLCKit/go2rtc loading.

### Deleted files

- `CameraViewer/Player/CameraPlayer.swift` (VLC), `CameraViewer/Player/StreamProxy.swift`
  (go2rtc), `CameraViewer/Window/DrawableView.swift` (replaced by `SampleBufferView`).
- `bin/go2rtc`, `Frameworks/VLCKit.xcframework`.

## Phasing

1. **Phase 1 — video only.** TLS+RTSP+RTP+H.264 (HEVC fallback) depacketize+VideoToolbox
   display, reconnect, zoom, aspect-lock. Mute is a no-op (no audio yet). Proves the pipeline.
2. **Phase 2 — audio.** AAC depacketize + `AVSampleBufferAudioRenderer` + sync; real mute.

Reaching first-frame-on-screen for Phase 1 is the key de-risking milestone.

## Testing

Pure modules get unit tests against **captured fixtures** (recorded SDP and RTP byte
sequences from the real cameras — captured with tokens stripped): `SDP.swift`,
`RTSPMessage.swift`, `DigestAuth.swift`, `RTPPacket.swift`, the three depacketizers
(single/AP/FU and STAP-A/FU-A reassembly, parameter-set extraction, AU boundary on
marker bit / timestamp change). The NWConnection/VideoToolbox glue is verified by running
the app against live cameras (per project convention).

## Key decisions

- **Drop SRTP entirely** — TLS already encrypts the TCP-interleaved media; SRTP is
  redundant and unused by every existing Protect integration. This removes the single
  largest risk/effort item from the original "native RTSP+SRTP" framing.
- **TCP-interleaved RTP, not UDP** — rides the one TLS socket (no second port, no NAT/UDP
  concerns), matches how RTSPS cameras ship, and is what `?enableSrtp` would otherwise
  guard.
- **`AVSampleBufferDisplayLayer` over a raw `VTDecompressionSession`** — it owns decode +
  render, is a `CALayer` (zoom ports free), and `DisplayImmediately` gives the lowest
  latency. We don't need `CVPixelBuffer`s.
- **Disable TLS cert verification** — the NVR ships a self-signed cert without an IP SAN;
  verification cannot succeed and go2rtc's long-standing `rtspx://` does the same. The
  link is still encrypted; we are not authenticating the server beyond reachability on the
  trusted LAN.
- **Vendor depacketizer logic from `retina` (MIT/Apache)** as reference/port rather than
  writing RFC 7798/6184 reassembly cold — its per-vendor edge-case history is the long tail
  we'd otherwise rediscover.
- **Preserve the `CameraPlayer` surface exactly** — confines the change to the player
  internals; `PiPWindowController` and the rest of the app are nearly untouched.
- **Strip `?enableSrtp` from configured URLs** rather than migrating the config file — the
  existing config format is unchanged (no migration; aligns with "ask before migrations").

## Confirmed by capture (2026-05-30)

Captured directly from the live cameras — RTSPS `DESCRIBE` on `10.0.0.1:7441` via
`openssl s_client`, cross-checked with `ffprobe` — across Back Door, Front Door,
Ellie's Room, and Garden. (Aside: the LAN was unreachable from the CLI not because of
routing but because of **macOS Local Network Privacy** — the terminal app needed the
Local Network grant. The `!` "reject" routes were a red herring: normal cloning-parent
templates, not the blocker.)

| # | Confirmed fact | Source |
|---|---|---|
| 1 | **Video is H.264 on every camera** (profile-level-id `4d4028`/`4d4032`/`4d0029`, Main/High). HEVC was *not* observed. → **H.264 is the primary depacketize/decode path (RFC 6184); HEVC (RFC 7798) kept as a defensive secondary.** | DESCRIBE ×4 + ffprobe |
| 2 | **1600×1200 @ 30 fps** (Back Door). | ffprobe |
| 3 | **Parameter sets are in the SDP** (`sprop-parameter-sets` = H.264 SPS/PPS). Build the `CMVideoFormatDescription` at DESCRIBE time, before the first RTP packet. | DESCRIBE |
| 4 | **No auth** — `200 OK` with only the URL token; no `401`/digest on any camera. → **Drop `DigestAuth`; no credentials in config.** | DESCRIBE ×4 |
| 5 | **No SRTP** — `?enableSrtp` only *adds* SDES `a=crypto` lines; without it the SDP is identical with plain RTP. → **strip `?enableSrtp`.** | DESCRIBE with/without |
| 6 | **Audio: two tracks offered** — AAC (`mpeg4-generic`, 48 kHz mono; 16 kHz on Ellie's Room; AAC-hbr, `config=1188`/`1408`) on `trackID=0`, Opus (48 kHz stereo) on `trackID=1`. → **select the AAC track**; ignore Opus. | DESCRIBE ×4 |
| 7 | **Transport** — RTSPS/TLS on `7441`, self-signed ("Media Server (www.ui.com)"), 90 kHz RTP clock, track control via `trackID=N` + `Content-Base`, TCP-interleaved RTP. | DESCRIBE |

**Still to measure (Phase 1, non-blocking):**
- **GOP / keyframe interval** — the connect-to-first-frame latency floor. fps = 30; GOP not yet counted. Gate `.playing` on the first IDR.
- **Which audio track carries data** — both AAC and Opus are *offered*; the current app's ffmpeg happens to copy Opus. Confirm the AAC track streams once SETUP/PLAYed; fall back to whichever has data.

**Plan deltas from these facts:**
- **H.264 primary, HEVC secondary** (was reversed) — simplifies decode; H.264 has the most mature VideoToolbox + RFC-6184 support.
- **`DigestAuth` removed** from the design (no auth observed); re-add only if a camera ever `401`s.
- **Audio Phase 2 stays simple** — AAC via `AVSampleBufferAudioRenderer`; Opus avoided by track selection.
- Config keeps `?enableSrtp` for the current VLC app; the native client strips it (no config migration — aligns with "ask before migrations").

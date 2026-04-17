# macOS Camera Viewer — Design

**Date:** 2026-04-17
**Status:** Design (pre-implementation)

## Summary

A single-window native macOS app that displays a local Unifi Protect camera feed in a Picture-in-Picture–style floating window. The window sits above every other window (including fullscreen apps) on every Space, is freely resizable from the corners with a locked aspect ratio, and hides its chrome (close, mute) until the cursor hovers.

The stream is consumed as RTSPS from a Unifi Protect controller on the local network — no cloud path, no transcoding sidecar.

## Goals and Non-Goals

**Goals**
- Show the camera feed, always visible, always on top.
- Minimal chrome — only visible on hover.
- Feels like Safari's Picture-in-Picture.
- Remembers position, size, and mute state between launches.
- Silently reconnects on network blips.

**Non-Goals**
- Multiple cameras (single stream only in v1).
- In-app settings UI (URL lives in a JSON file on disk).
- App Store distribution (LGPL video stack; not compatible).
- Notarization / DMG packaging (ad-hoc signed, personal use).
- Launch-at-login.
- UI automation tests.

## Inputs and Constraints

- **Stream URL format:** `rtsps://<controller-ip>:7441/<camera-id>?enableSrtp`
  - Example in use: `rtsps://10.0.0.1:7441/ccA66GZzFoKTCyxD?enableSrtp`
  - Stream ships H.264 video and AAC audio; `enableSrtp` means SRTP-encrypted.
- **macOS floor:** 13 Ventura.
- **Hardware:** Apple Silicon + Intel (VLCKit ships universal binaries).

## Toolchain

| Piece | Choice | Why |
| --- | --- | --- |
| Language | Swift 5.10+ | Native, modern. |
| UI | AppKit for `NSWindow` + menu-bar; SwiftUI inside the window via `NSHostingView` for the chrome overlay. | SwiftUI alone cannot express the window levels and collection behavior PiP needs; AppKit gives full control for the shell while SwiftUI is ergonomic for the small overlay. |
| Video | VLCKit 3.6.x via Swift Package Manager (`https://code.videolan.org/videolan/VLCKit.git`). | `AVPlayer` does not speak RTSP. VLCKit handles RTSPS + SRTP with no extra config. |
| Build | Xcode, single project, single app target + tests target. | Smallest viable structure. |

No other third-party dependencies.

## User-Facing Behavior

### Window

- Exactly one `NSWindow` in the app.
- Subclass of `NSWindow` called `PiPWindow`.
- `level = .screenSaver` — above normal windows, fullscreen apps, and the Dock.
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` — follows the user across Spaces and stays visible over fullscreen apps.
- `styleMask = [.borderless, .resizable]`; `titlebarAppearsTransparent = true`; `isMovableByWindowBackground = true`.
- `contentAspectRatio` is set to the video's reported dimensions as soon as the first frame is decoded, locking the aspect ratio during resize.
- Resizable from the four corners only. Edge resize is disabled by returning `.none` from a hit-test override for edge regions (the corner hit-boxes retain the standard resize cursor).
- **Size bounds:** min 320×180; max = current screen's `visibleFrame` minus 40 px margin.
- **First-launch size & position:** 480×270 (16:9), bottom-right of the main screen with a 16 px inset. Once the first video frame arrives, the window's content aspect ratio is locked to the stream's reported dimensions; if the camera reports a non-16:9 aspect the window resizes to match, preserving the shorter dimension.
- **Drag to move:** from anywhere on the window.
- **Corner snap:** on drag-end, if the window's center is within 80 px of any screen corner, animate (150 ms) to that corner with an 8 px inset. If not close to any corner, leave the window where the user dropped it.
- Subtle 1 px `white @ 10% opacity` stroke around the window for definition against bright and dark backgrounds.

### Chrome Overlay

- A 36 px tall translucent panel floated at the top-center of the video.
- Backed by `NSVisualEffectView` with material `.hudWindow`.
- Two SF Symbol buttons only:
  - **Close:** `xmark.circle.fill` — quits the app.
  - **Mute toggle:** `speaker.slash.fill` ↔ `speaker.wave.2.fill`.
- **Visibility:**
  - Hidden by default (alpha 0).
  - Fades in over 150 ms on `mouseEntered`.
  - Starts a 2 s timer on `mouseExited`; on timer fire, fades out over 250 ms.
  - Moving back into the window cancels the timer.
- Implemented with one `NSTrackingArea` covering the window's content view, publishing hover state via Combine to the SwiftUI overlay.

### Menu-Bar Presence

- `LSUIElement = true` — no Dock icon, no app menu, not in ⌘-Tab.
- `NSStatusItem` with SF Symbol `video.fill`.
- Menu items:
  1. Reveal Config in Finder
  2. Reconnect
  3. ────
  4. Quit
- Status icon switches to `video.slash.fill` while the player is in error/retry state, and back to `video.fill` when playing.
- Hiding the window is intentionally not offered — the close button and the Quit menu item both exit the app. If the user wants the feed out of the way temporarily, they move or resize the window.

## Internals

### Module / File Layout

```
CameraViewer/
├── CameraViewerApp.swift          // @main, NSApplicationDelegate, lifecycle
├── AppDelegate.swift              // builds window + menu bar, wires everything up
├── Window/
│   ├── PiPWindow.swift            // NSWindow subclass: levels, collectionBehavior, aspect ratio, edge-resize block
│   ├── PiPWindowController.swift  // owns the window, persists frame, handles corner-snap, mediates player state
│   └── CornerSnap.swift           // pure function: (windowFrame, screenFrame, snapThreshold, inset) -> snapped frame
├── Player/
│   ├── CameraPlayer.swift         // wraps VLCMediaPlayer: play(url), pause(), setMuted(), publishes state
│   └── ReconnectPolicy.swift      // pure: next delay given consecutive-failure count; exponential cap
├── Chrome/
│   ├── ChromeOverlay.swift        // SwiftUI view: close + mute buttons, alpha bound to hover state
│   └── HoverTrackingView.swift    // NSView with NSTrackingArea, publishes hover state via Combine
├── Config/
│   ├── AppConfig.swift            // Codable { rtspsURL: URL }; load from ~/Library/Application Support/CameraViewer/config.json
│   └── Persistence.swift          // UserDefaults wrapper: windowFrame (NSRect), isMuted (Bool)
└── MenuBar/
    └── StatusItemController.swift // builds NSStatusItem + NSMenu, updates icon on player state changes
```

Each file aims to stay under ~150 lines. The three purely functional pieces — `CornerSnap`, `ReconnectPolicy`, `AppConfig` codec — are unit-tested without touching AppKit.

### Data Flow

```
launch → AppDelegate.applicationDidFinishLaunching
          ├── AppConfig.load()
          │     └─ missing file? write stub, open in TextEdit, show NSAlert, exit
          ├── Persistence.loadFrame() / loadMuted()
          ├── PiPWindowController(config: ..., initialFrame: ..., muted: ...)
          │     ├── constructs PiPWindow
          │     ├── installs HoverTrackingView
          │     ├── installs ChromeOverlay via NSHostingView
          │     ├── creates CameraPlayer, calls play(config.rtspsURL)
          │     └── subscribes to CameraPlayer state → updates status icon
          └── StatusItemController(controller: ...)

resize drag end  → Persistence.saveFrame(window.frame)
mute toggle      → CameraPlayer.setMuted(..); Persistence.saveMuted(..)
window move end  → CornerSnap.snap(...) → animated setFrame if within threshold
stream error     → ReconnectPolicy.nextDelay → schedule CameraPlayer.play(url) retry
```

State lives in three places only:
1. **`CameraPlayer`** — playback state (playing / buffering / error), published via Combine.
2. **`Persistence` / UserDefaults** — `windowFrame` (encoded `NSRect`), `isMuted` (`Bool`). Written on resize-end, move-end, and mute toggle.
3. **`AppConfig`** — disk-backed JSON, read once at launch and again on "Reconnect".

### Threading

- **Main thread:** all AppKit, SwiftUI, and `VLCMediaPlayer` calls. VLCKit requires its media player object to be touched from a single thread; main is simplest.
- **VLC internal threads:** decode and network — not touched by our code.
- **Reconnect timer:** main `RunLoop`; backoff math is pure and synchronous.

### Reconnect Policy

- Listen for `VLCMediaPlayerStateError` and `VLCMediaPlayerStateEnded`.
- On either, schedule retry with delay sequence `1 s, 2 s, 4 s, 8 s, 10 s, 10 s, …` (capped at 10 s).
- Counter resets to zero on `VLCMediaPlayerStatePlaying`.
- Status icon reflects retrying vs playing (see Menu-Bar Presence).
- After 30 s of continuous failure, the menu gains a "Last error: …" item with the most recent VLC error string, so the user can see why. The item is removed the next time the player enters the `playing` state.

### Error Handling Philosophy

- **Missing config file:** one-time `NSAlert` with the path, writes a stub file pre-populated with a commented placeholder URL, opens it in TextEdit, exits. Not silent.
- **Bad / unreachable URL:** VLC reports error state → reconnect loop handles it. Status icon goes to the error variant after the first retry.
- **Internally impossible states** (e.g., window controller without a window): `assertionFailure` in debug, no defensive try/catch.
- Only `AppConfig.load` and VLC's async state callbacks have real fail paths. Everything else trusts its preconditions.

### Configuration File

- Path: `~/Library/Application Support/CameraViewer/config.json`
- Shape:
  ```json
  { "rtspsURL": "rtsps://10.0.0.1:7441/YOUR_CAMERA_ID?enableSrtp" }
  ```
- On first launch the directory is created and a stub file written with a placeholder URL and a top-level `"_comment"` key explaining where to find the real URL (in the Protect web UI → Settings → Advanced → RTSP).
- "Reveal Config in Finder" menu item opens the containing directory with the file selected.
- "Reconnect" menu item re-reads the file and rebinds the player to the (potentially new) URL.

## Build & Run

- **Xcode project:** single project at the repo root, one app target (`CameraViewer`) and one tests target (`CameraViewerTests`).
- **Info.plist** (via "Generate Info.plist File" build setting):
  - `LSUIElement = YES`
  - `NSCameraUsageDescription = "Displays your Unifi Protect camera feed."`
  - `NSAppTransportSecurity.NSAllowsLocalNetworking = YES`
- **Entitlements:** Hardened Runtime on, `com.apple.security.network.client = YES`. App Sandbox off (VLCKit + arbitrary LAN RTSP would need several extra entitlements and the app isn't going to the App Store).
- **Signing:** "Sign to Run Locally" (ad-hoc). No paid developer account required.
- **Day-to-day:** `⌘R` in Xcode to build and launch. Drag the Release `.app` into `/Applications` for a permanent install.

## Testing

Proportional to a ~500-line single-window app.

### Unit tests (`CameraViewerTests`)

All pure, fast, AppKit-free:

1. **`CornerSnap`** — table-driven cases covering:
   - Window centre near each of the four screen corners → snaps with correct 8 px inset.
   - Window centre in the middle of the screen → no snap (returns original frame).
   - Window larger than the screen edge inset → clamped correctly.
2. **`ReconnectPolicy`** — sequence is `1, 2, 4, 8, 10, 10, 10`; `reset()` returns to `1`.
3. **`AppConfig`** — encode a sample config, decode, assert round-trip equality; decode a malformed config and assert the expected error.

### Manual smoke-test checklist (in `README.md`)

1. Launch → window appears bottom-right, video starts muted.
2. Hover → chrome fades in; stop hovering → chrome fades out after ~2 s.
3. Mute button toggles audio.
4. Drag window near top-left corner → snaps to top-left.
5. Resize from a corner → aspect ratio stays locked (16:9 for a standard Unifi stream).
6. Swipe to another Space → window follows.
7. Enter fullscreen in another app → camera window stays on top.
8. Pull Ethernet / disable Wi-Fi → after ~5 s, status icon switches to the error variant; restore network → stream recovers without interaction.
9. Quit and relaunch → window returns to the same position, size, and mute state.

TDD applies to the three pure modules (tests first). AppKit plumbing is integration-tested via the manual checklist.

## Distribution (out of scope for v1)

Ad-hoc signed, local build only. Notarization, DMG packaging, and a Sparkle auto-update feed are potential follow-ups if the app ever leaves the author's machine.

## Open Questions / Future Work

- **Launch at login** via `SMAppService` — skipped for v1 (requires a helper target).
- **In-app settings UI** — skipped for v1 (JSON file is sufficient for one camera).
- **Multiple cameras** — would introduce list management, per-window state, and a real Preferences window. Separate design if/when the need appears.
- **App Store–compatible build** — would require replacing VLCKit with a non-LGPL decoder and turning sandboxing back on. Probably not worth it for this tool.

## Licensing Note

VLCKit is LGPL. Personal use is fine. Redistribution requires either dynamic linking (which the `.xcframework` provides by default) and shipping the VLCKit license text, or replacing the decoder. Re-mention in the `README.md`.

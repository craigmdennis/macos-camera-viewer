# Feature Changelog

## Interaction fixes (2026-08-23)

Five bugs from real use (GitHub #4 – #8): the stream kept running after closing the window, an unfocused window needed two clicks to drag, holding space beeped, zoom reset during live resize, and the resize hit target was too small.

### Files changed

| File | Change |
|------|--------|
| `CameraViewer/Window/PiPWindowController.swift` | `hideWindow()` now cancels the reconnect timer and stops the player; `showWindow()` restarts it with the spinner. Chrome is hosted in a private `FirstMouseHostingView` (`acceptsFirstMouse → true`). `windowDidResize` replaces `windowDidEndLiveResize` for frame persistence; `SampleBufferView.onLayout` re-asserts the zoom transform. |
| `CameraViewer/Player/NativeCameraPlayer.swift` | `stop()` sets `state = .idle` so the menu bar reads "Idle" while hidden. |
| `CameraViewer/Chrome/HoverTrackingView.swift` | Space key events are swallowed only when `event.window` is the PiP window. A click within `EdgeResize.band` of an edge/corner resizes the window manually on drag; `mouseMoved` sets matching resize cursors. |
| `CameraViewer/Player/SampleBufferView.swift` | `onLayout` callback; `setFrameSize` marks `needsLayout`. |
| `CameraViewer/Window/EdgeResize.swift` | New. Pure edge detection (flipped view coords) and frame math honouring `contentAspectRatio`, min/max size, and the fixed opposite edge. Unit-tested. |
| `CameraViewerTests/EdgeResizeTests.swift` | New. 6 tests. |
| `CameraViewer/Window/CornerSnap.swift` | Threshold now measures the window's origin against its docked position (was centre-to-screen-corner, which only fired with the window three-quarters off-screen). New `flickTarget(windowFrame:velocity:screenVisibleFrame:)` projects the release velocity 0.25 s, clamped to the screen, before snapping. |
| `CameraViewer/Window/WindowSpring.swift` | New. Pure `Spring.step` (semi-implicit Euler, stiffness 220, damping 24, slightly underdamped) plus `WindowSpring`, a 60 Hz timer driving `setFrameOrigin`. |
| `CameraViewerTests/CornerSnapTests.swift`, `SpringTests.swift` | Snap tests rewritten for the origin-based threshold; flick and spring-settle tests added. |

### Key decisions

- **Hide == stop** — an ordered-out window is indistinguishable from a quit to the user, so it must drop the camera connection; show reconnects
- **First-mouse on the hosting view, not hit-test passthrough** — the SwiftUI chrome is the hit-test target and forwards unhandled mouse events up the responder chain; accepting the activating click there fixes both drag and the buttons in one place
- **Swallow space per-window** — the Settings window's text fields live in another window, so `event.window === self.window` keeps them working
- **Re-apply zoom from `layout()`** — AppKit resets a backing layer's transform in the layout pass, and that pass runs per live-resize tick, so the hook must be there rather than in a window delegate
- **Snap from `mouseUp`, with velocity** — `HoverTrackingView` owns the move gesture, so it reports `onDragBegin`/`onDragEnd(velocity)`; the 150 ms `windowDidMove` debounce (which also snapped mid-drag on a pause) is gone. A pause over 0.1 s before release zeroes the velocity
- **Spring by hand** — `NSAnimationContext` cannot overshoot, so the elastic dock is a manual spring; grabbing the window mid-animation cancels it. Releasing away from a corner leaves the window where it is
- **Manual edge resize** — AppKit exposes no way to widen a borderless window's resize band; the view claims a 10 px band and does the geometry itself. Diagonal cursors use `NSCursor.frameResize` on macOS 15+, arrow below

## Zoom & pan (2026-05-29)

Added pinch-free zoom on the camera feed. ⌘ + scroll zooms 1×–8×; dragging while zoomed pans; double-click resets. Implemented as a `CATransform3D` on the player's drawable layer — VLC is not involved. A zoom-level badge appears at bottom-center while zoomed.

### Files changed

| File | Change |
|------|--------|
| `CameraViewer/Player/ZoomState.swift` | New. Pure struct modelling `screen = scale·p + translation` (corner-anchored). `applyScaleDelta(_:focus:viewSize:)` zooms toward the cursor; `applyPanDelta`/`reclamp` keep `translation ∈ [-(scale-1)·dim, 0]` so the feed always covers the view. Unit-tested. |
| `CameraViewer/Player/ZoomController.swift` | New. Owns `ZoomState`, weak ref to the drawable view; converts the cursor to view coords for focal zoom and applies an **anchor-compensated** transform (`τ = t + anchor·bounds·(s−1)`) so it's correct regardless of AppKit's anchor point. Re-applies on resize. Publishes `@Published scale`. |
| `CameraViewer/Window/DrawableView.swift` | New. `NSView` whose `hitTest` returns nil, so the sibling `HoverTrackingView` (which accepts first mouse) is the consistent event target — fixes panning when the app isn't focused. |
| `CameraViewer/Chrome/HoverTrackingView.swift` | Added `zoomController`; ⌘-gated `scrollWheel`; double-click resets. Click-drag moves the window (manual, `mouseDownCanMoveWindow = false`); when zoomed, a long press (0.35s) arms grab-style 1:1 video-pan with an open/closed-hand cursor. The pan delta's y is inverted to match the layer's y-down transform space. |
| `CameraViewer/Chrome/ChromeOverlay.swift` | Added `zoomScale` param and a `ZoomBadge` pill, shown when `zoomScale > 1.0` and fading with the chrome when the pointer leaves the window. |
| `CameraViewer/Window/PiPWindowController.swift` | Uses `DrawableView`, constructs `ZoomController(view:)`, wires it to the hover view, subscribes to `$scale`, re-applies on resize/aspect-lock. Persists zoom via `ZoomController.onChange` and restores it on launch (re-applied once the layer is laid out). |
| `CameraViewer/Config/Persistence.swift` | Added `loadZoom`/`saveZoom` (scale as Double, translation as `NSStringFromPoint`). |
| `CameraViewerTests/ZoomStateTests.swift` | New. 11 tests: focal zoom keeps the cursor point fixed, coverage invariant (no black bars), pan/scale clamping, reclamp-on-resize, reset. |
| `project.yml` | Source-of-truth fixes that previously lived only in the generated pbxproj: `PRODUCT_NAME`, `PRODUCT_MODULE_NAME`, test `TEST_HOST`/`BUNDLE_LOADER`, a shared scheme with a test action, and `ARCHS: arm64` (VLCKit is arm64-only). |

### Key decisions

- **CALayer transform, not VLC crop** — GPU compositing op, fully reversible to identity; VLC never knows
- **Corner-anchored model + coverage clamp** — `translation ∈ [-(scale-1)·dim, 0]` *guarantees* the scaled feed covers the window, so it can never inset from the edges (the original center-symmetric clamp allowed over-pan into black)
- **Focal-point zoom** — zoom is centred on the cursor by solving for the translation that keeps the content point under the cursor fixed
- **Anchor compensation in the controller** — rather than fighting AppKit's backing-layer geometry, compute the transform translation to net out to the desired mapping for whatever anchor AppKit uses
- **⌘ + scroll** is the macOS-native zoom gesture (Maps, Preview); needs zero new UI
- **Long-press to pan, click-drag to move the window** — window movement stays the default even when zoomed; pan is opt-in via a long press, so the two never conflict. AppKit evaluates `mouseDownCanMoveWindow` once per gesture and can't be flipped mid-press, so the window is moved manually via screen-coordinate deltas
- **Pan is grab-style and 1:1** — the feed tracks the cursor exactly; the vertical axis is inverted because the drawable layer's transform space is y-down
- **Zoom badge fades with the chrome** — visible while the pointer is over the window, fades out when it leaves
- **Zoom persists across restarts** — scale + translation saved globally (the last-active camera is already restored by name, so the last view is reconstructed); restored values are re-clamped to the current geometry so a saved pan can never expose an edge

## Multi-camera selection (2026-04-20)

Replaced single-camera config with a named camera array. Users select the active camera from a menu-bar submenu; the selection persists across launches.

### Config format changed

Old (`rtspsURL` key no longer works):
```json
{ "rtspsURL": "rtsps://..." }
```

New:
```json
{
  "cameras": [
    { "name": "Front Door", "uri": "rtsps://10.0.0.1:7441/CAMERA_ID?enableSrtp" }
  ]
}
```

### Files changed

| File | Change |
|------|--------|
| `CameraViewer/Config/AppConfig.swift` | `AppConfig` now holds `cameras: [CameraConfig]`; `CameraConfig` has `name: String` and `uri: URL`; `load()` rejects empty arrays |
| `CameraViewer/Config/Persistence.swift` | Added `selectedCameraName` load/save (UserDefaults key `selectedCameraName`) |
| `CameraViewer/MenuBar/StatusItemController.swift` | Added `cameras`, `selectedCameraName`, `onSelectCamera` closures; Cameras submenu rebuilt on every `menuWillOpen` |
| `CameraViewer/AppDelegate.swift` | Resolves active camera on launch by persisted name (fallback to `cameras[0]`); wires `onSelectCamera` through proxy restart + `updateStreamURL` |
| `CameraViewerTests/AppConfigTests.swift` | Full rewrite for new model; covers empty-array and missing-cameras-key error paths |
| `CameraViewerTests/PersistenceTests.swift` | Added `selectedCameraName` round-trip tests |
| `config.example.json` | Updated to multi-camera format |
| `Makefile` | `APP_NAME` updated to `Camera Viewer` (with space) |
| `README.md` | Configuration section updated for new format |

### Key decisions

- Camera selection persists by **name**, not index — survives reordering
- `onReconnect` reloads config from disk so URI edits take effect without restarting
- Submenu rebuilt fresh on every open — no change observation needed
- `StreamProxy` (go2rtc subprocess) is restarted on every camera switch

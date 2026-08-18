# Feature Changelog

## Multi-stream layouts (2026-08-18)

Added 2-camera (stacked) and 4-camera (2×2 grid) PiP layouts alongside the original
single-camera view. Each tile runs its own independent player/reconnect loop and camera
assignment; only one tile's audio plays at a time. Clicking a tile's video jumps straight
to single view on that camera, with a one-tap way back to the grid. The window's live
resize is aspect-locked to whatever keeps every tile filling its space (computed from the
real camera resolution), so there's no letterboxing in any layout.

### Files changed

| File | Change |
|------|--------|
| `CameraViewer/Window/PiPLayout.swift` | New. Pure enum (`.single`/`.split2`/`.grid4`) with `tileCount`, `minWindowSize`, and `frames(for:containerSize:spacing:)` — the tile geometry, shared by the AppKit grid view and the SwiftUI chrome overlay so they can't drift apart. Unit-tested. |
| `CameraViewer/Window/StreamTileController.swift` | New. One tile's player + drawable view + independent `ReconnectPolicy`, mirroring the single-view reconnect loop but scoped per stream. |
| `CameraViewer/Window/TileGridView.swift` | New. `NSView` positioning tile drawable views via `PiPLayout.frames`, re-run on every `setFrameSize`. |
| `CameraViewer/Window/MultiStreamController.swift` | New. Owns a split/grid layout end-to-end: tiles, mute exclusivity, per-tile camera persistence, combined menu-bar state, and the grid's computed aspect ratio (from the first assigned tile's real video size). |
| `CameraViewer/Window/PiPWindowController.swift` | Added `setLayout`/`switchToSingleCamera`; mounts either the original single-view tree or a `MultiStreamController.contentView` into the shared `hoverView`. Replaced `NSWindow.contentAspectRatio` (crashed AppKit's live-resize geometry when toggled to `.zero` for multi layouts) with a self-computed clamp in `windowWillResize`, shared by single and multi layouts via `lockAspectRatio`. Click-vs-drag on `HoverTrackingView` resolves which tile was tapped. |
| `CameraViewer/Chrome/ChromeStyle.swift` | New. `VisualEffectBlur` + `hudCapsule()` extracted out of `ChromeOverlay` so single and multi chrome share the same HUD look. |
| `CameraViewer/Chrome/TileCapsule.swift` | New. Per-tile mute + camera-picker capsule; hides the camera name (icons only) once the tile is too narrow for it to fit without overlapping the global controls. |
| `CameraViewer/Chrome/MultiChromeOverlay.swift` | New. Global close/layout controls + one `TileCapsule` per tile, positioned via the same `PiPLayout.frames` the AppKit grid uses. |
| `CameraViewer/Chrome/ChromeOverlay.swift` | Added a layout-switcher menu next to close/mute, and a one-tap "back to grid" button shown only after a tile click (not after an explicit layout-menu selection). |
| `CameraViewer/Chrome/HoverTrackingView.swift` | Added `onClick`, firing on a plain click (no drag, no pan) — used to resolve which tile was tapped. |
| `CameraViewer/Config/Persistence.swift` | Added `loadLayout`/`saveLayout` and `loadTileCameraNames`/`saveTileCameraNames` (per-layout, empty-string sentinel for "unassigned"). |
| `CameraViewer/MenuBar/StatusItemController.swift` | Added a "Layout" submenu mirroring the existing "Cameras" submenu. |
| `CameraViewerTests/PiPLayoutTests.swift` | New. Tile counts, frame geometry (no overlap, covers the container), min-size sanity. |

### Key decisions

- **`.single` mode's internals are untouched** — split/grid layouts are a parallel view tree that swaps into the same window, so zoom/pan, per-camera zoom persistence, and aspect-lock for the single view carry zero risk from this change
- **Manual per-tile camera assignment**, not auto-filled from the config list order — persisted per layout so split2 and grid4 remember different assignments independently
- **One audio stream at a time** — muting a tile force-mutes the others; not persisted, always starts muted on layout entry
- **Zoom/pan disabled in multi layouts** — each tile just letterboxes via `.resizeAspect`; avoids per-tile hit-testing/persistence complexity for a secondary use case
- **`NSWindow.contentAspectRatio` dropped entirely** in favor of a delegate-based clamp (`windowWillResize`) — setting the native property to `.zero` when leaving single view crashed AppKit's live-resize internals (`EXC_BREAKPOINT` in `_adjustNeedsDisplayRegionForNewFrame:`), confirmed via a real crash report; the self-computed clamp sidesteps that AppKit code path entirely and works identically for both single and multi layouts
- **Grid aspect ratio from one real camera's resolution**, not a fixed guess — in practice all cameras on one NVR share a resolution, so any assigned tile is representative; recomputed whenever the reference tile's camera changes
- **Explicit frame sync on remount** — `NSView.addSubview` does not retroactively resize a view to the superview's current bounds, only on the *next* resize via autoresizingMask; re-attaching the single view's `playerDrawableView`/`chromeHostingView` after a stint in a differently-sized multi layout needed an explicit `frame = hoverView.bounds` before re-adding

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

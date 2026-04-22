# Zoom Feature Design

**Date:** 2026-04-22

## Overview

Add the ability to zoom into the camera feed and pan around at the zoomed level, with a reset gesture. Zoom is implemented as a CALayer transform on the video drawable view — no VLC API involvement.

## Interaction model

| Gesture | Action |
|---------|--------|
| ⌘ + scroll wheel | Zoom in/out |
| Drag (when zoomed) | Pan the video |
| Drag (when at 1×) | Move the window (unchanged) |
| Double-click | Reset zoom and pan to 1× / centered |

Zoom range: 1× (min) to 8× (max). Offset is clamped at all times so the video always fills the window — no black bars visible during pan.

## Architecture

### New files

**`CameraViewer/Player/ZoomState.swift`**
Pure struct. Holds `scale: CGFloat` and `offset: CGPoint`. Exposes:
- `mutating func applyScaleDelta(_ delta: CGFloat, viewSize: CGSize)` — multiplies scale by delta, clamps to 1–8×, re-clamps offset
- `mutating func applyPanDelta(_ delta: CGPoint, viewSize: CGSize)` — adds delta to offset, clamps
- `mutating func reset()` — returns to scale 1.0, offset .zero
- `var transform: CATransform3D` — computed translate-then-scale transform
- `var isZoomed: Bool` — true when scale > 1 (with small epsilon)

Offset clamping formula: `maxOffset = (scale - 1) / 2 * viewDimension` per axis.

**`CameraViewer/Player/ZoomController.swift`**
Owns a `ZoomState`. Holds a weak reference to the player drawable `CALayer`. Publishes `@Published var scale: CGFloat` so consumers can observe zoom changes.

Methods:
- `handleScroll(_ event: NSEvent, viewSize: CGSize)` — converts `scrollingDeltaY` to a scale multiplier (sensitivity ≈ 0.005), delegates to `ZoomState`, applies transform
- `handlePanDelta(_ delta: CGPoint, viewSize: CGSize)` — delegates to `ZoomState`, applies transform
- `reset()` — resets state, applies transform with a 0.25s ease-out animation
- `var isZoomed: Bool` — proxies `ZoomState.isZoomed`

Transform application: non-animated updates disable `CATransaction` actions to avoid implicit animations interfering with gesture tracking. Reset uses an explicit `CATransaction` with `kCAMediaTimingFunctionEaseOut`.

### Modified files

**`CameraViewer/Chrome/HoverTrackingView.swift`**

Add `var zoomController: ZoomController?` (set by `PiPWindowController` after construction).

Override:
- `scrollWheel(_:)` — if `event.modifierFlags.contains(.command)` and `zoomController != nil`: forward to `zoomController.handleScroll`; otherwise `super.scrollWheel`
- `mouseDownCanMoveWindow` — return `false` when `zoomController?.isZoomed == true`; AppKit checks this before intercepting drag as a window move
- `mouseDown(_:)` — `clickCount == 2` → `zoomController?.reset()`; also record `dragStart = event.locationInWindow` for pan tracking
- `mouseDragged(_:)` — when zoomed: compute delta from `dragStart`, call `zoomController?.handlePanDelta`, update `dragStart`; when not zoomed: `super` (window drag)
- `mouseUp(_:)` — clear `dragStart`

**`CameraViewer/Chrome/ChromeOverlay.swift`**

Add `zoomScale: CGFloat` parameter. Add a `ZoomBadge` view:
- Small pill at bottom-center (above the 10pt bottom padding)
- Shows `"2.1×"` formatted to one decimal place
- Visible when `zoomScale > 1.0`, hidden otherwise
- Uses the same `VisualEffectBlur` capsule background as the existing chrome bar
- Animated with `.easeInOut(duration: 0.15)` on the `zoomScale > 1.0` condition

**`CameraViewer/Window/PiPWindowController.swift`**

- Construct `ZoomController(layer: playerDrawableView.layer!)` after `super.init()`
- Set `hoverView.zoomController = zoomController`
- Subscribe to `zoomController.$scale` on main thread, call `refreshChrome()` on each emission
- Pass `zoomController.scale` to `currentOverlay()` → `ChromeOverlay(zoomScale:)`

### Test file

**`CameraViewerTests/ZoomStateTests.swift`**
Unit tests for:
- Scale clamping at min (1×) and max (8×)
- Offset clamping: at 2×, max offset = viewSize/2 in each axis
- `transform` produces correct scale and translation components
- `reset()` returns to identity values
- `isZoomed` false at 1.0, true above threshold

## Key decisions

- **CALayer transform, not VLC crop** — transform works at the GPU compositing layer with no VLC API involved; crop geometry API is less predictable and harder to reverse
- **⌘ modifier required** — without it, plain scroll could be ambiguous if the window ever gains scrollable UI; ⌘+scroll is the macOS-standard zoom gesture (Maps, Preview, etc.)
- **`mouseDownCanMoveWindow` override** — this is how AppKit decides whether a click-drag moves the window; returning `false` when zoomed lets the view handle the drag as a pan without disabling `isMovableByWindowBackground` globally
- **Double-click to reset** — consistent with macOS zoom conventions (Maps, image viewers); no extra button needed in the chrome bar
- **`@Published scale` on ZoomController** — matches the existing `@Published` pattern on `CameraPlayer`; lets `PiPWindowController` subscribe and refresh chrome without coupling ZoomController to the view layer
- **Zoom badge not in hover chrome bar** — the badge is purely informational and should be visible while actively zooming/panning, independent of hover state

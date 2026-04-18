# Corner Radius — Match System PIP

**Date:** 2026-04-18

## Goal

Apply a 12pt corner radius to the viewer window to match the visual style of the macOS system Picture-in-Picture window.

## Approach

Content view layer masking: make the window non-opaque so clipped corners are transparent, then set `cornerRadius` and `masksToBounds` on the content view's layer.

## Changes

### `PiPWindow.swift`

- `isOpaque = false` (was `true`)
- `backgroundColor = .clear` (was `.black`)

### `PiPWindowController.swift`

After `hoverView.wantsLayer = true`, add:

```swift
hoverView.layer?.cornerRadius = 12
hoverView.layer?.masksToBounds = true
```

## Notes

- The existing `hasShadow = true` on the window naturally follows the rounded shape once the window is non-opaque.
- The black fill is preserved via `hoverView.layer?.backgroundColor = NSColor.black.cgColor`, which is already set.
- `masksToBounds = true` clips VLC's `CAOpenGLLayer` (inside `playerDrawableView`) to the rounded rect.

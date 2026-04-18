# Corner Radius Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply a 12pt corner radius to the viewer window to match the macOS system PIP window.

**Architecture:** Make `PiPWindow` non-opaque so clipped corners are transparent, then set `cornerRadius` and `masksToBounds` on `hoverView`'s backing layer in `PiPWindowController`. No new files needed.

**Tech Stack:** AppKit, CALayer

---

### Task 1: Make PiPWindow non-opaque

This is required for the clipped corners to appear transparent rather than filled with the window background colour.

**Files:**
- Modify: `CameraViewer/Window/PiPWindow.swift:17-18`

- [ ] **Step 1: Apply changes**

In `PiPWindow.init`, replace:

```swift
backgroundColor = .black
isOpaque = true
```

with:

```swift
backgroundColor = .clear
isOpaque = false
```

- [ ] **Step 2: Build**

```
xcodebuild -scheme CameraViewer build
```

Expected: Build Succeeded

- [ ] **Step 3: Commit**

```bash
git add CameraViewer/Window/PiPWindow.swift
git commit -m "feat: make PiPWindow non-opaque to support corner radius"
```

---

### Task 2: Apply corner radius to content view layer

`hoverView` is the window's content view and already has `wantsLayer = true`. Setting `cornerRadius` and `masksToBounds` clips all subviews — including VLC's `CAOpenGLLayer` inside `playerDrawableView` — to the rounded rect.

**Files:**
- Modify: `CameraViewer/Window/PiPWindowController.swift:39-41`

- [ ] **Step 1: Apply changes**

In `PiPWindowController.init`, after the existing `hoverView.layer?.borderColor` line, add:

```swift
hoverView.layer?.cornerRadius = 12
hoverView.layer?.masksToBounds = true
```

The block should read:

```swift
let hoverView = HoverTrackingView(frame: NSRect(origin: .zero, size: initialFrame.size))
hoverView.autoresizingMask = [.width, .height]
hoverView.wantsLayer = true
hoverView.layer?.backgroundColor = NSColor.black.cgColor
hoverView.layer?.borderWidth = 1
hoverView.layer?.borderColor = NSColor(white: 1, alpha: 0.1).cgColor
hoverView.layer?.cornerRadius = 12
hoverView.layer?.masksToBounds = true
self.hoverView = hoverView
```

- [ ] **Step 2: Build**

```
xcodebuild -scheme CameraViewer build
```

Expected: Build Succeeded

- [ ] **Step 3: Visual verification**

Run the app. The viewer window should have rounded corners matching the system PIP window. The black background, border, shadow, and video content should all be clipped to the rounded rect.

- [ ] **Step 4: Commit**

```bash
git add CameraViewer/Window/PiPWindowController.swift
git commit -m "feat: apply 12pt corner radius to match system PIP window"
```

import AppKit

// VLC renders into this view's backing layer. It is transparent to mouse input so
// the sibling HoverTrackingView (which accepts first mouse) is the consistent event
// target — otherwise a plain NSView here would swallow clicks and block panning when
// the app is not focused (scroll-to-zoom still works because scrollWheel needs no
// key window, but mouseDown does).
final class DrawableView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

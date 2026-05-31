import AppKit
import AVFoundation

/// Layer-backed view whose backing layer IS the `AVSampleBufferDisplayLayer` the decoder
/// renders into. Input-transparent (`hitTest → nil`) so the sibling `HoverTrackingView`
/// stays the consistent event target — same trick the old VLC `DrawableView` used. The
/// zoom transform is applied to this view's backing layer exactly as before (ASBDL is a
/// `CALayer`), so `ZoomController` works unchanged.
final class SampleBufferView: NSView {
    var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }

    override func makeBackingLayer() -> CALayer {
        let layer = AVSampleBufferDisplayLayer()
        layer.videoGravity = .resizeAspect
        return layer
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

import AppKit
import Combine
import QuartzCore

// Bridges gestures to the pure ZoomState and applies the result as a transform on
// the drawable's backing layer. Publishes `scale` so the window controller can refresh
// the chrome badge using the same Combine pattern as CameraPlayer.state.
final class ZoomController: ObservableObject {
    @Published private(set) var scale: CGFloat = 1.0

    // Called whenever zoom/pan changes so the owner can persist it.
    var onChange: ((CGFloat, CGPoint) -> Void)?

    private var state = ZoomState()
    private weak var view: NSView?

    // scrollingDeltaY → scale multiplier. Tuned so a normal swipe moves a fraction
    // of a zoom step rather than snapping across the range.
    private let scrollSensitivity: CGFloat = 0.005

    init(view: NSView?) {
        self.view = view
    }

    var isZoomed: Bool { state.isZoomed }

    func handleScroll(_ event: NSEvent) {
        guard let view else { return }
        let multiplier = 1 + event.scrollingDeltaY * scrollSensitivity
        guard multiplier > 0 else { return }
        state.applyScaleDelta(multiplier, focus: focus(of: event, in: view), viewSize: view.bounds.size)
        applyTransform(animated: false)
    }

    func handlePanDelta(_ delta: CGPoint) {
        guard let view else { return }
        state.applyPanDelta(delta, viewSize: view.bounds.size)
        applyTransform(animated: false)
    }

    func reset() {
        state.reset()
        applyTransform(animated: true)
    }

    func restore(scale: CGFloat, translation: CGPoint) {
        guard let view else { return }
        state.restore(scale: scale, translation: translation, viewSize: view.bounds.size)
        applyTransform(animated: false)
    }

    // Re-clamp and re-apply after the view resizes; the transform is also re-asserted
    // because AppKit can reset a backing layer's transform during layout.
    func viewDidResize() {
        guard let view else { return }
        state.reclamp(viewSize: view.bounds.size)
        applyTransform(animated: false)
    }

    private func focus(of event: NSEvent, in view: NSView) -> CGPoint {
        let p = view.convert(event.locationInWindow, from: nil)
        // Match the layer's y-down transform space so zoom centres on the cursor.
        return CGPoint(x: p.x, y: view.bounds.height - p.y)
    }

    private func applyTransform(animated: Bool) {
        guard let layer = view?.layer else { return }
        let bounds = layer.bounds.size
        let anchor = layer.anchorPoint
        let s = state.scale
        let t = state.translation

        // Compensate for the layer's anchor point so the net mapping is exactly
        // screen = s·p + t regardless of where AppKit places the anchor:
        // τ = t + (anchor·bounds)·(s - 1).
        let ax = anchor.x * bounds.width
        let ay = anchor.y * bounds.height
        let tau = CGPoint(x: t.x + ax * (s - 1), y: t.y + ay * (s - 1))

        var transform = CATransform3DMakeTranslation(tau.x, tau.y, 0)
        transform = CATransform3DScale(transform, s, s, 1)

        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.25)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        layer.transform = transform
        CATransaction.commit()
        scale = s
        onChange?(s, t)
    }
}

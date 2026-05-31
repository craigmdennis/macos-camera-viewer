import CoreGraphics

// Pure zoom/pan model. The realised screen mapping is `screen = scale·p + translation`
// (corner-anchored, in view points). All clamping keeps the scaled content covering
// the view, so the camera feed can never inset from the edges. AppKit-free → unit-tested.
struct ZoomState: Equatable {
    static let minScale: CGFloat = 1.0
    static let maxScale: CGFloat = 8.0
    private static let epsilon: CGFloat = 0.001

    private(set) var scale: CGFloat = 1.0
    private(set) var translation: CGPoint = .zero

    var isZoomed: Bool { scale > Self.minScale + Self.epsilon }

    // Zoom toward `focus` (in view coords) so the content under the cursor stays put.
    // Deriving from screen = S·p + T: the content point under the cursor is
    // p* = (focus - T)/S, and we solve for the new T that keeps S'·p* + T' = focus.
    mutating func applyScaleDelta(_ factor: CGFloat, focus: CGPoint, viewSize: CGSize) {
        let oldScale = scale
        scale = (scale * factor).clamped(to: Self.minScale...Self.maxScale)
        let ratio = scale / oldScale
        translation.x = focus.x - ratio * (focus.x - translation.x)
        translation.y = focus.y - ratio * (focus.y - translation.y)
        clamp(viewSize: viewSize)
    }

    // Grab semantics: the content follows the cursor.
    mutating func applyPanDelta(_ delta: CGPoint, viewSize: CGSize) {
        translation.x += delta.x
        translation.y += delta.y
        clamp(viewSize: viewSize)
    }

    mutating func reset() {
        scale = Self.minScale
        translation = .zero
    }

    // Restore persisted values, clamped to the current view so a saved pan can't
    // expose an edge if the geometry differs from when it was saved.
    mutating func restore(scale: CGFloat, translation: CGPoint, viewSize: CGSize) {
        self.scale = scale.clamped(to: Self.minScale...Self.maxScale)
        self.translation = translation
        clamp(viewSize: viewSize)
    }

    mutating func reclamp(viewSize: CGSize) {
        clamp(viewSize: viewSize)
    }

    // Content spans [translation, scale·dim + translation]; to cover [0, dim] the
    // translation must sit in [-(scale - 1)·dim, 0] on each axis.
    private mutating func clamp(viewSize: CGSize) {
        let minX = -(scale - 1) * viewSize.width
        let minY = -(scale - 1) * viewSize.height
        translation.x = translation.x.clamped(to: minX...0)
        translation.y = translation.y.clamped(to: minY...0)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

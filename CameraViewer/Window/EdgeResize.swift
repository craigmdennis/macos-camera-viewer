import AppKit

/// Pure geometry for the in-view edge/corner resize. AppKit's own resize band on a
/// borderless window is a few px wide, so the view claims a wider band and resizes the
/// window itself. Points are in the view's flipped coordinate space (y down).
enum EdgeResize {
    static let band: CGFloat = 10

    struct Edges: OptionSet, Equatable {
        let rawValue: Int
        static let left   = Edges(rawValue: 1 << 0)
        static let right  = Edges(rawValue: 1 << 1)
        static let top    = Edges(rawValue: 1 << 2)
        static let bottom = Edges(rawValue: 1 << 3)
    }

    static func edges(at p: CGPoint, in size: CGSize, band: CGFloat = band) -> Edges {
        var e: Edges = []
        if p.x < band { e.insert(.left) }
        if p.x > size.width - band { e.insert(.right) }
        if p.y < band { e.insert(.top) }
        if p.y > size.height - band { e.insert(.bottom) }
        return e
    }

    /// New window frame for a drag of `delta` (screen coords, y up) from `start`.
    /// `aspect` is the window's contentAspectRatio, or nil/zero to resize freely.
    static func frame(start: NSRect, edges: Edges, delta: CGPoint,
                      aspect: CGSize?, min: CGSize, max: CGSize) -> NSRect {
        var w = start.width, h = start.height
        if edges.contains(.right) { w += delta.x }
        if edges.contains(.left) { w -= delta.x }
        if edges.contains(.top) { h += delta.y }
        if edges.contains(.bottom) { h -= delta.y }
        w = w.clamped(to: min.width...max.width)
        h = h.clamped(to: min.height...max.height)

        if let aspect, aspect.width > 0, aspect.height > 0 {
            let ratio = aspect.height / aspect.width
            let horizontal = !edges.isDisjoint(with: [.left, .right])
            if horizontal { h = w * ratio } else { w = h / ratio }
            if h < min.height || h > max.height {
                h = h.clamped(to: min.height...max.height); w = h / ratio
            }
            if w < min.width || w > max.width {
                w = w.clamped(to: min.width...max.width); h = w * ratio
            }
        }

        let x = edges.contains(.left) ? start.maxX - w : start.minX
        let y = edges.contains(.bottom) ? start.maxY - h : start.minY
        return NSRect(x: x, y: y, width: w, height: h)
    }

    static func cursor(for edges: Edges) -> NSCursor? {
        guard !edges.isEmpty else { return nil }
        if #available(macOS 15, *) {
            let position: NSCursor.FrameResizePosition
            switch edges {
            case .left: position = .left
            case .right: position = .right
            case .top: position = .top
            case .bottom: position = .bottom
            case [.top, .left]: position = .topLeft
            case [.top, .right]: position = .topRight
            case [.bottom, .left]: position = .bottomLeft
            default: position = .bottomRight
            }
            return .frameResize(position: position, directions: .all)
        }
        // ponytail: no public diagonal cursor before macOS 15; corners keep the arrow.
        if edges == .left || edges == .right { return .resizeLeftRight }
        if edges == .top || edges == .bottom { return .resizeUpDown }
        return nil
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

import AppKit

enum CornerSnap {
    static let defaultThreshold: CGFloat = 80
    static let defaultInset: CGFloat = 8

    enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    /// Snaps when the window's own origin is within `threshold` of where it would dock;
    /// anywhere else the frame is returned unchanged, so free positioning still works.
    static func snap(
        windowFrame: NSRect,
        screenVisibleFrame screen: NSRect,
        threshold: CGFloat = defaultThreshold,
        inset: CGFloat = defaultInset
    ) -> NSRect {
        let candidates: [NSRect] = [.topLeft, .topRight, .bottomLeft, .bottomRight].map {
            frame(for: $0, size: windowFrame.size, in: screen, inset: inset)
        }
        let nearest = candidates.min { distance($0.origin, windowFrame.origin) < distance($1.origin, windowFrame.origin) }!
        return distance(nearest.origin, windowFrame.origin) <= threshold ? nearest : windowFrame
    }

    /// Snap target after a release with `velocity` (points/sec): the frame is projected
    /// forward so a flick toward a corner docks there. Nil when nothing is near enough.
    static func flickTarget(windowFrame: NSRect, velocity: CGPoint, screenVisibleFrame screen: NSRect,
                            projection: CGFloat = 0.25) -> NSRect? {
        var projected = windowFrame
        // Clamp to the screen so a hard flick past the edge still counts as "toward the corner".
        projected.origin.x = min(max(projected.origin.x + velocity.x * projection, screen.minX),
                                 screen.maxX - windowFrame.width)
        projected.origin.y = min(max(projected.origin.y + velocity.y * projection, screen.minY),
                                 screen.maxY - windowFrame.height)
        let snapped = snap(windowFrame: projected, screenVisibleFrame: screen)
        return snapped == projected ? nil : snapped
    }

    private static func distance(_ a: NSPoint, _ b: NSPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    private static func frame(for corner: Corner, size: NSSize, in screen: NSRect, inset: CGFloat) -> NSRect {
        switch corner {
        case .topLeft:
            return NSRect(x: screen.minX + inset,
                          y: screen.maxY - size.height - inset,
                          width: size.width, height: size.height)
        case .topRight:
            return NSRect(x: screen.maxX - size.width - inset,
                          y: screen.maxY - size.height - inset,
                          width: size.width, height: size.height)
        case .bottomLeft:
            return NSRect(x: screen.minX + inset,
                          y: screen.minY + inset,
                          width: size.width, height: size.height)
        case .bottomRight:
            return NSRect(x: screen.maxX - size.width - inset,
                          y: screen.minY + inset,
                          width: size.width, height: size.height)
        }
    }
}

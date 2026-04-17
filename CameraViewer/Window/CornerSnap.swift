import AppKit

enum CornerSnap {
    static let defaultThreshold: CGFloat = 80
    static let defaultInset: CGFloat = 8

    enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    static func snap(
        windowFrame: NSRect,
        screenVisibleFrame screen: NSRect,
        threshold: CGFloat = defaultThreshold,
        inset: CGFloat = defaultInset
    ) -> NSRect {
        let center = NSPoint(x: windowFrame.midX, y: windowFrame.midY)
        let corners: [(Corner, NSPoint)] = [
            (.topLeft,     NSPoint(x: screen.minX, y: screen.maxY)),
            (.topRight,    NSPoint(x: screen.maxX, y: screen.maxY)),
            (.bottomLeft,  NSPoint(x: screen.minX, y: screen.minY)),
            (.bottomRight, NSPoint(x: screen.maxX, y: screen.minY))
        ]

        let nearest = corners.min { distance($0.1, center) < distance($1.1, center) }!
        guard distance(nearest.1, center) <= threshold else {
            return windowFrame
        }
        return frame(for: nearest.0, size: windowFrame.size, in: screen, inset: inset)
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

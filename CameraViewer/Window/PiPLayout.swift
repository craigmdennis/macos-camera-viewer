import CoreGraphics
import AppKit

enum PiPLayout: String, CaseIterable, Codable {
    case single, split2, grid4

    var tileCount: Int {
        switch self {
        case .single: return 1
        case .split2: return 2
        case .grid4: return 4
        }
    }

    var displayName: String {
        switch self {
        case .single: return "Single Camera"
        case .split2: return "2 Cameras"
        case .grid4: return "4 Cameras"
        }
    }

    var minWindowSize: NSSize {
        switch self {
        case .single: return NSSize(width: 320, height: 180)
        case .split2: return NSSize(width: 200, height: 200)
        case .grid4: return NSSize(width: 240, height: 180)
        }
    }

    /// Tile rects for this layout within `containerSize`, separated by `spacing`.
    /// Pure geometry — shared by the AppKit grid view and the SwiftUI chrome overlay so
    /// their tile positions can never drift apart.
    static func frames(for layout: PiPLayout, containerSize: CGSize, spacing: CGFloat) -> [CGRect] {
        switch layout {
        case .single:
            return [CGRect(origin: .zero, size: containerSize)]
        case .split2:
            let half = (containerSize.height - spacing) / 2
            return [
                CGRect(x: 0, y: half + spacing, width: containerSize.width, height: half),
                CGRect(x: 0, y: 0, width: containerSize.width, height: half)
            ]
        case .grid4:
            let halfW = (containerSize.width - spacing) / 2
            let halfH = (containerSize.height - spacing) / 2
            return [
                CGRect(x: 0, y: halfH + spacing, width: halfW, height: halfH),
                CGRect(x: halfW + spacing, y: halfH + spacing, width: halfW, height: halfH),
                CGRect(x: 0, y: 0, width: halfW, height: halfH),
                CGRect(x: halfW + spacing, y: 0, width: halfW, height: halfH)
            ]
        }
    }
}

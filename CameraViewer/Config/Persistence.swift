import Foundation
import AppKit

struct Persistence {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let windowFrame = "windowFrame"
        static let isMuted = "isMuted"
        static let selectedCameraName = "selectedCameraName"
        static let zoomScale = "zoomScale"
        static let zoomTranslation = "zoomTranslation"
        static let layout = "pipLayout"
        static let tileCameras = "tileCameras"
    }

    func loadFrame() -> NSRect? {
        guard let string = defaults.string(forKey: Key.windowFrame) else { return nil }
        let rect = NSRectFromString(string)
        return rect == .zero ? nil : rect
    }

    func saveFrame(_ rect: NSRect) {
        defaults.set(NSStringFromRect(rect), forKey: Key.windowFrame)
    }

    func loadMuted() -> Bool {
        defaults.object(forKey: Key.isMuted) as? Bool ?? true
    }

    func saveMuted(_ muted: Bool) {
        defaults.set(muted, forKey: Key.isMuted)
    }

    func loadSelectedCameraName() -> String? {
        defaults.string(forKey: Key.selectedCameraName)
    }

    func saveSelectedCameraName(_ name: String) {
        defaults.set(name, forKey: Key.selectedCameraName)
    }

    // Zoom/pan is persisted per camera (keyed by name) so each camera keeps its own
    // framing. Pre-per-camera global keys are abandoned (zoom resets once, harmless).
    func loadZoom(camera: String) -> (scale: CGFloat, translation: CGPoint)? {
        let scaleKey = Key.zoomScale + "." + camera
        guard defaults.object(forKey: scaleKey) != nil else { return nil }
        let scale = CGFloat(defaults.double(forKey: scaleKey))
        let translation = NSPointFromString(defaults.string(forKey: Key.zoomTranslation + "." + camera) ?? "")
        return (scale, translation)
    }

    func saveZoom(camera: String, scale: CGFloat, translation: CGPoint) {
        defaults.set(Double(scale), forKey: Key.zoomScale + "." + camera)
        defaults.set(NSStringFromPoint(translation), forKey: Key.zoomTranslation + "." + camera)
    }

    func loadLayout() -> PiPLayout {
        guard let raw = defaults.string(forKey: Key.layout), let layout = PiPLayout(rawValue: raw) else {
            return .single
        }
        return layout
    }

    func saveLayout(_ layout: PiPLayout) {
        defaults.set(layout.rawValue, forKey: Key.layout)
    }

    /// Per-tile camera assignment for a split/grid layout, keyed by tile index. An empty
    /// string is the "unassigned" sentinel (UserDefaults arrays can't hold nil).
    func loadTileCameraNames(_ layout: PiPLayout) -> [String?] {
        guard let names = defaults.array(forKey: Key.tileCameras + "." + layout.rawValue) as? [String] else {
            return Array(repeating: nil, count: layout.tileCount)
        }
        return names.map { $0.isEmpty ? nil : $0 }
    }

    func saveTileCameraNames(_ names: [String?], layout: PiPLayout) {
        defaults.set(names.map { $0 ?? "" }, forKey: Key.tileCameras + "." + layout.rawValue)
    }
}

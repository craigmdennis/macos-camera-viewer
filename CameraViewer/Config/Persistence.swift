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
}

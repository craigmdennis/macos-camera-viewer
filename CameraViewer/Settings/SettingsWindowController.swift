import AppKit
import SwiftUI

/// Hosts `SettingsView` in a standard macOS window. Single reusable instance — reopening
/// brings the existing window forward rather than spawning duplicates.
final class SettingsWindowController: NSWindowController {
    convenience init(store: CameraStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Camera Viewer Settings"
        window.contentView = NSHostingView(rootView: SettingsView(store: store))
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

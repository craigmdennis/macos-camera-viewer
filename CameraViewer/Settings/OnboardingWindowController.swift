import AppKit
import SwiftUI

/// Hosts `OnboardingView` for first launch. Closes once the first camera is added (the
/// viewer takes over). Quitting the window before adding a camera terminates the app,
/// since there's nothing to show yet.
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let store: CameraStore
    private var completed = false

    init(store: CameraStore) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 320),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Welcome"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: OnboardingView(store: store) { [weak self] in
            self?.complete()
        })
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func complete() {
        completed = true
        close()
    }

    // Closing onboarding without adding a camera = nothing to run.
    func windowWillClose(_ notification: Notification) {
        if !completed { NSApp.terminate(nil) }
    }
}

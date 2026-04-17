import AppKit

final class PiPWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        hasShadow = true
        backgroundColor = .black
        isOpaque = true
        hidesOnDeactivate = false

        contentMinSize = NSSize(width: 320, height: 180)
        applyMaxSizeForCurrentScreen()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        applyMaxSizeForCurrentScreen()
    }

    private func applyMaxSizeForCurrentScreen() {
        let visible = screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 3840, height: 2160)
        let margin: CGFloat = 40
        contentMaxSize = NSSize(
            width: max(contentMinSize.width, visible.width - margin * 2),
            height: max(contentMinSize.height, visible.height - margin * 2)
        )
    }
}

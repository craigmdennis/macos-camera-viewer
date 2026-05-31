import AppKit
import Combine

final class HoverTrackingView: NSView {
    let isHovered = CurrentValueSubject<Bool, Never>(false)

    // Set by PiPWindowController after construction.
    var zoomController: ZoomController?

    private var trackingArea: NSTrackingArea?
    private var dragOrigin: NSPoint?              // pan reference, in window coords
    private var windowDragStart: (mouse: NSPoint, origin: NSPoint)?
    private var longPressTimer: Timer?
    private var isPanning = false

    private let longPressDuration: TimeInterval = 0.35

    // Space-to-pan: tracked via a local key monitor (the borderless window's responder
    // chain makes keyDown unreliable otherwise). True while the space bar is held.
    private var spaceHeld = false
    private var keyMonitor: Any?
    private static let spaceKeyCode: UInt16 = 49

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered.send(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered.send(false)
    }

    // MARK: - Space key tracking

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                guard let self, event.keyCode == Self.spaceKeyCode else { return event }
                self.spaceHeld = (event.type == .keyDown)
                // Don't swallow — a focused text field still needs the space key.
                return event
            }
        } else if window == nil, let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
            spaceHeld = false
        }
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    // MARK: - Drag: window-move by default, video-pan via long-press / space / middle button

    // We move the window manually, so keep AppKit from also moving it.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            cancelLongPress()
            zoomController?.reset()
            return
        }
        isPanning = false
        dragOrigin = event.locationInWindow
        windowDragStart = (NSEvent.mouseLocation, window?.frame.origin ?? .zero)

        guard zoomController?.isZoomed == true else { return }

        // Space held → pan immediately. Otherwise a long press arms pan mode; until then
        // the drag moves the window. The timer runs in .common so it fires while held.
        if spaceHeld {
            beginPanMode()
        } else {
            let timer = Timer(timeInterval: longPressDuration, repeats: false) { [weak self] _ in
                self?.beginPanMode()
            }
            RunLoop.current.add(timer, forMode: .common)
            longPressTimer = timer
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if isPanning {
            applyPan(to: event.locationInWindow)
            return
        }
        // A drag before pan mode arms means "move the window".
        cancelLongPress()
        guard let start = windowDragStart else { return }
        let now = NSEvent.mouseLocation
        window?.setFrameOrigin(NSPoint(x: start.origin.x + (now.x - start.mouse.x),
                                       y: start.origin.y + (now.y - start.mouse.y)))
    }

    override func mouseUp(with event: NSEvent) {
        endGesture()
    }

    // MARK: - Middle button: pan immediately when zoomed

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2, zoomController?.isZoomed == true else {
            super.otherMouseDown(with: event); return
        }
        dragOrigin = event.locationInWindow
        beginPanMode()
    }

    override func otherMouseDragged(with event: NSEvent) {
        if isPanning { applyPan(to: event.locationInWindow) } else { super.otherMouseDragged(with: event) }
    }

    override func otherMouseUp(with event: NSEvent) {
        if isPanning { endGesture() } else { super.otherMouseUp(with: event) }
    }

    // MARK: - Pan helpers

    private func beginPanMode() {
        cancelLongPress()
        guard zoomController?.isZoomed == true, dragOrigin != nil else { return }
        isPanning = true
        NSCursor.closedHand.set()
    }

    /// Grab-style 1:1 pan. Layer transform space is y-down, so invert y.
    private func applyPan(to location: NSPoint) {
        guard let origin = dragOrigin else { return }
        zoomController?.handlePanDelta(CGPoint(x: location.x - origin.x, y: origin.y - location.y))
        dragOrigin = location
        NSCursor.closedHand.set()
    }

    private func endGesture() {
        cancelLongPress()
        dragOrigin = nil
        windowDragStart = nil
        isPanning = false
        NSCursor.arrow.set()
    }

    private func cancelLongPress() {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let zoomController {
            zoomController.handleScroll(event)
        } else {
            super.scrollWheel(with: event)
        }
    }

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

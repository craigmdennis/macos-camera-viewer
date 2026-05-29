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

    // MARK: - Drag: window-move by default, video-pan after a long press

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

        // Only when zoomed does holding still arm video-pan mode; otherwise the
        // drag just moves the window. The timer must run in event-tracking mode
        // so it fires while the button is held.
        if zoomController?.isZoomed == true {
            let timer = Timer(timeInterval: longPressDuration, repeats: false) { [weak self] _ in
                self?.beginPanMode()
            }
            RunLoop.current.add(timer, forMode: .common)
            longPressTimer = timer
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if isPanning {
            guard let origin = dragOrigin else { return }
            // Grab-style 1:1 pan; layer transform space is y-down so invert y.
            let location = event.locationInWindow
            let delta = CGPoint(x: location.x - origin.x, y: origin.y - location.y)
            zoomController?.handlePanDelta(delta)
            dragOrigin = location
            NSCursor.closedHand.set()
            return
        }
        // A drag before the long press fires means "move the window".
        cancelLongPress()
        guard let start = windowDragStart else { return }
        let now = NSEvent.mouseLocation
        window?.setFrameOrigin(NSPoint(x: start.origin.x + (now.x - start.mouse.x),
                                       y: start.origin.y + (now.y - start.mouse.y)))
    }

    override func mouseUp(with event: NSEvent) {
        cancelLongPress()
        dragOrigin = nil
        windowDragStart = nil
        isPanning = false
        NSCursor.arrow.set()
        super.mouseUp(with: event)
    }

    private func beginPanMode() {
        cancelLongPress()
        guard zoomController?.isZoomed == true, dragOrigin != nil else { return }
        isPanning = true
        NSCursor.openHand.set()
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

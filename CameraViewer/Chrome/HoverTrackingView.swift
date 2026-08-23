import AppKit
import Combine

final class HoverTrackingView: NSView {
    let isHovered = CurrentValueSubject<Bool, Never>(false)

    // Set by PiPWindowController after construction.
    var zoomController: ZoomController?

    private var trackingArea: NSTrackingArea?
    private var dragOrigin: NSPoint?              // pan reference, in window coords
    private var windowDragStart: (mouse: NSPoint, origin: NSPoint)?
    private var resize: (edges: EdgeResize.Edges, mouse: NSPoint, frame: NSRect)?
    private var lastDrag: (point: NSPoint, time: TimeInterval)?
    private var dragVelocity = CGPoint.zero          // points/sec, screen coords

    // Window-move gesture lifecycle, for the owner's snap animation.
    var onDragBegin: (() -> Void)?
    var onDragEnd: ((CGPoint) -> Void)?              // release velocity
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
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
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
        NSCursor.arrow.set()
    }

    // MARK: - Space key tracking

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                guard let self, event.keyCode == Self.spaceKeyCode else { return event }
                self.spaceHeld = (event.type == .keyDown)
                // Swallow only for this window: nothing here handles keys, so letting the
                // event through makes AppKit beep on every key-repeat. Other windows
                // (Settings text fields) still get the space key.
                return event.window === self.window ? nil : event
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
        let edges = EdgeResize.edges(at: convert(event.locationInWindow, from: nil), in: bounds.size)
        if !edges.isEmpty, let window {
            resize = (edges, NSEvent.mouseLocation, window.frame)
            return
        }
        dragOrigin = event.locationInWindow
        windowDragStart = (NSEvent.mouseLocation, window?.frame.origin ?? .zero)
        lastDrag = (NSEvent.mouseLocation, event.timestamp)
        dragVelocity = .zero
        onDragBegin?()

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
        if let resize, let window {
            let now = NSEvent.mouseLocation
            let frame = EdgeResize.frame(
                start: resize.frame, edges: resize.edges,
                delta: CGPoint(x: now.x - resize.mouse.x, y: now.y - resize.mouse.y),
                aspect: window.contentAspectRatio,
                min: window.contentMinSize, max: window.contentMaxSize)
            window.setFrame(frame, display: true)
            return
        }
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
        if let last = lastDrag, event.timestamp > last.time {
            let dt = event.timestamp - last.time
            // Light smoothing so one jittery event does not decide the flick direction.
            dragVelocity.x = 0.5 * dragVelocity.x + 0.5 * (now.x - last.point.x) / dt
            dragVelocity.y = 0.5 * dragVelocity.y + 0.5 * (now.y - last.point.y) / dt
        }
        lastDrag = (now, event.timestamp)
    }

    override func mouseUp(with event: NSEvent) {
        if windowDragStart != nil, !isPanning, let last = lastDrag {
            // A pause before release means no flick.
            let velocity = event.timestamp - last.time > 0.1 ? .zero : dragVelocity
            onDragEnd?(velocity)
        }
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
        resize = nil
        lastDrag = nil
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

    // Wider-than-AppKit resize band needs matching cursors; .activeAlways + mouseMoved
    // is the tracking area we already have, so update the cursor from there.
    override func mouseMoved(with event: NSEvent) {
        let edges = EdgeResize.edges(at: convert(event.locationInWindow, from: nil), in: bounds.size)
        (EdgeResize.cursor(for: edges) ?? .arrow).set()
    }

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

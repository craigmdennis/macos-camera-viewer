import AppKit
import Combine
import SwiftUI

final class PiPWindowController: NSObject, NSWindowDelegate {
    let window: PiPWindow
    let player: CameraPlayer

    private let persistence: Persistence
    private var streamURL: URL
    private let hoverView: HoverTrackingView
    private let playerDrawableView: NSView
    private var chromeHostingView: NSHostingView<ChromeOverlay>!
    private var reconnectPolicy = ReconnectPolicy()
    private var reconnectTimer: Timer?
    private var hoverFadeOutTimer: Timer?
    private var dragEndDebounce: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var chromeVisible = false
    private var isLoading = true
    private var videoSizeTimer: Timer?

    // Exposed so StatusItemController can observe state.
    var playerStatePublisher: AnyPublisher<CameraPlayer.State, Never> {
        player.$state.eraseToAnyPublisher()
    }

    init(streamURL: URL, persistence: Persistence = Persistence()) {
        self.streamURL = streamURL
        self.persistence = persistence

        let initialFrame = Self.initialFrame(persisted: persistence.loadFrame())
        let window = PiPWindow(contentRect: initialFrame)
        self.window = window

        let hoverView = HoverTrackingView(frame: NSRect(origin: .zero, size: initialFrame.size))
        hoverView.autoresizingMask = [.width, .height]
        hoverView.wantsLayer = true
        hoverView.layer?.backgroundColor = NSColor.black.cgColor
        hoverView.layer?.borderWidth = 1
        hoverView.layer?.borderColor = NSColor(white: 1, alpha: 0.1).cgColor
        self.hoverView = hoverView

        // VLC's CAOpenGLLayer attaches to the drawable's backing layer at play time,
        // landing on top of any existing subviews. Using a dedicated child view keeps
        // the chrome overlay as a sibling above the player.
        let playerDrawableView = NSView(frame: NSRect(origin: .zero, size: initialFrame.size))
        playerDrawableView.autoresizingMask = [.width, .height]
        playerDrawableView.wantsLayer = true
        self.playerDrawableView = playerDrawableView

        self.player = CameraPlayer(drawable: playerDrawableView, initiallyMuted: persistence.loadMuted())

        super.init()

        window.contentView = hoverView
        hoverView.addSubview(playerDrawableView)
        window.delegate = self

        installChrome()
        observeHover()
        observePlayerState()

        // Defer the initial frame-set and order-front to the next runloop tick so we
        // don't trigger a layout pass from inside applicationDidFinishLaunching — that
        // was the source of the "-layoutSubtreeIfNeeded while already laying out" warning.
        let initialFrameCopy = initialFrame
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window.setFrame(initialFrameCopy, display: true)
            self.window.makeKeyAndOrderFront(nil)
            self.player.play(url: self.streamURL)
        }
    }

    func updateStreamURL(_ url: URL) {
        streamURL = url
        reconnectPolicy.reset()
        player.stop()
        player.play(url: url)
    }

    deinit {
        reconnectTimer?.invalidate()
        hoverFadeOutTimer?.invalidate()
        dragEndDebounce?.invalidate()
        videoSizeTimer?.invalidate()
    }

    func showWindow() {
        window.makeKeyAndOrderFront(nil)
    }

    func hideWindow() {
        window.orderOut(nil)
    }

    var isWindowVisible: Bool { window.isVisible }

    // MARK: - Layout

    private static func initialFrame(persisted: NSRect?) -> NSRect {
        if let p = persisted, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(p) }) {
            return p
        }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 480, height: 270)
        let inset: CGFloat = 16
        return NSRect(x: screen.maxX - size.width - inset,
                      y: screen.minY + inset,
                      width: size.width, height: size.height)
    }

    private func installChrome() {
        let hosting = NSHostingView(rootView: currentOverlay())
        hosting.frame = hoverView.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        hoverView.addSubview(hosting)
        chromeHostingView = hosting
    }

    private func currentOverlay() -> ChromeOverlay {
        ChromeOverlay(
            isVisible: chromeVisible,
            isMuted: player.isMuted,
            isLoading: isLoading,
            onClose: { [weak self] in self?.hideWindow() },
            onToggleMute: { [weak self] in self?.toggleMute() }
        )
    }

    private func refreshChrome() {
        // Update the SwiftUI tree off the current run-loop iteration to avoid
        // "called -layoutSubtreeIfNeeded on a view which is already being laid out".
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.chromeHostingView.rootView = self.currentOverlay()
        }
    }

    // MARK: - Hover

    private func observeHover() {
        hoverView.isHovered
            .removeDuplicates()
            .sink { [weak self] hovered in self?.handleHover(hovered) }
            .store(in: &cancellables)
    }

    private func handleHover(_ hovered: Bool) {
        hoverFadeOutTimer?.invalidate()
        if hovered {
            chromeVisible = true
            refreshChrome()
        } else {
            hoverFadeOutTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                self?.chromeVisible = false
                self?.refreshChrome()
            }
        }
    }

    // MARK: - Mute

    private func toggleMute() {
        let next = !player.isMuted
        player.setMuted(next)
        persistence.saveMuted(next)
        refreshChrome()
    }

    // MARK: - Player state / reconnect

    private func observePlayerState() {
        player.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.handlePlayerState(state) }
            .store(in: &cancellables)
    }

    private func handlePlayerState(_ state: CameraPlayer.State) {
        NSLog("PiPWindowController: player state → %@", String(describing: state))
        switch state {
        case .playing:
            reconnectPolicy.reset()
            reconnectTimer?.invalidate()
            isLoading = false
            refreshChrome()
            scheduleVideoSizeLock()
        case .error:
            isLoading = true
            refreshChrome()
            scheduleReconnect()
        case .idle, .opening, .buffering:
            // Don't re-show the spinner once playing has started; VLC re-enters
            // buffering mid-stream on format changes and during the startup flush.
            break
        }
    }

    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        let delay = reconnectPolicy.recordFailure()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.player.play(url: self.streamURL)
        }
    }

    // VLC populates videoSize asynchronously after the .playing state fires.
    // Poll until it's available (typically within 1-2 ticks).
    private func scheduleVideoSizeLock() {
        videoSizeTimer?.invalidate()
        videoSizeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if let size = self.player.videoSize, size.width > 0, size.height > 0 {
                timer.invalidate()
                self.applyAspectRatio(size)
            }
        }
    }

    private func applyAspectRatio(_ size: CGSize) {
        window.contentAspectRatio = size
        let ar = size.height / size.width
        let currentWidth = window.frame.width
        let targetHeight = (currentWidth * ar).rounded()
        guard abs(targetHeight - window.frame.height) > 2 else { return }
        var newFrame = window.frame
        newFrame.size.height = targetHeight
        newFrame.origin.y = window.frame.maxY - targetHeight
        window.setFrame(newFrame, display: true, animate: true)
        persistence.saveFrame(newFrame)
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        persistence.saveFrame(window.frame)
        scheduleDragEndSnap()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        persistence.saveFrame(window.frame)
    }

    // Corner snap on drag-end. AppKit doesn't fire a discrete "drag ended" event
    // for windows moved via isMovableByWindowBackground, so we debounce windowDidMove
    // — when no further moves arrive for 150 ms, treat that as the drag ending.
    func installDragEndSnap() {
        // No-op for API compatibility with AppDelegate; the snap is wired through
        // windowDidMove → scheduleDragEndSnap → snapToNearestCorner.
    }

    private func scheduleDragEndSnap() {
        dragEndDebounce?.invalidate()
        dragEndDebounce = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            self?.snapToNearestCorner()
        }
    }

    private func snapToNearestCorner() {
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let snapped = CornerSnap.snap(windowFrame: window.frame, screenVisibleFrame: visible)
        guard snapped != window.frame else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            window.animator().setFrame(snapped, display: true)
        }
        persistence.saveFrame(snapped)
    }
}

import AppKit
import Combine
import SwiftUI

final class PiPWindowController: NSObject, NSWindowDelegate {
    let window: PiPWindow
    let player: NativeCameraPlayer

    private let persistence: Persistence
    private var streamURL: URL
    private let hoverView: HoverTrackingView
    private let playerDrawableView: SampleBufferView
    private var zoomController: ZoomController!
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
    var playerStatePublisher: AnyPublisher<NativeCameraPlayer.State, Never> {
        player.$state.eraseToAnyPublisher()
    }

    // Camera list/selection for the in-viewer picker. Injected by AppDelegate, which owns
    // the camera list and the switch path (persist selection + restart stream). Defaults
    // are empty so the controller works standalone (e.g. in tests).
    var cameras: () -> [CameraConfig] = { [] }
    var selectedCameraName: () -> String? = { nil }
    var onSelectCamera: (CameraConfig) -> Void = { _ in }

    // Called by AppDelegate after a camera switch so the picker label refreshes.
    func refreshChromeForCameraChange() { refreshChrome() }

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
        hoverView.layer?.cornerRadius = 12
        hoverView.layer?.masksToBounds = true
        self.hoverView = hoverView

        // The display layer renders into this view's backing layer. A dedicated child
        // view keeps the chrome overlay as a sibling above the player, and its
        // input-transparent hitTest keeps HoverTrackingView the event target.
        let playerDrawableView = SampleBufferView(frame: NSRect(origin: .zero, size: initialFrame.size))
        playerDrawableView.autoresizingMask = [.width, .height]
        self.playerDrawableView = playerDrawableView

        self.player = NativeCameraPlayer(view: playerDrawableView, initiallyMuted: persistence.loadMuted())

        super.init()

        zoomController = ZoomController(view: playerDrawableView)
        zoomController.onChange = { [weak self] scale, translation in
            guard let self, let name = self.selectedCameraName() else { return }
            self.persistence.saveZoom(camera: name, scale: scale, translation: translation)
        }
        // Initial restore is deferred to the makeKeyAndOrderFront block below, after the
        // layer is laid out AND AppDelegate has wired `selectedCameraName`.
        hoverView.zoomController = zoomController

        window.contentView = hoverView
        hoverView.addSubview(playerDrawableView)
        window.delegate = self

        installChrome()
        observeHover()
        observePlayerState()
        observeZoom()

        // Defer the initial frame-set and order-front to the next runloop tick so we
        // don't trigger a layout pass from inside applicationDidFinishLaunching — that
        // was the source of the "-layoutSubtreeIfNeeded while already laying out" warning.
        let initialFrameCopy = initialFrame
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window.setFrame(initialFrameCopy, display: true)
            self.window.makeKeyAndOrderFront(nil)
            // Apply this camera's saved zoom now the layer is laid out (init-time
            // bounds may be zero, which throws off the anchor compensation).
            self.restoreZoomForCurrentCamera()
            self.player.play(url: self.streamURL)
        }
    }

    func updateStreamURL(_ url: URL) {
        streamURL = url
        reconnectPolicy.reset()
        player.stop()
        player.play(url: url)
        // Switching cameras: apply the new camera's saved zoom (or reset to 1×).
        restoreZoomForCurrentCamera()
    }

    /// Apply the persisted zoom/pan for the currently-selected camera, or reset to 1× if
    /// none is saved. Re-clamps to current window geometry.
    private func restoreZoomForCurrentCamera() {
        guard let name = selectedCameraName() else { zoomController.viewDidResize(); return }
        if let saved = persistence.loadZoom(camera: name) {
            zoomController.restore(scale: saved.scale, translation: saved.translation)
        } else {
            zoomController.reset()
        }
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
            zoomScale: zoomController.scale,
            cameras: cameras(),
            selectedCameraName: selectedCameraName(),
            onClose: { [weak self] in self?.hideWindow() },
            onToggleMute: { [weak self] in self?.toggleMute() },
            onSelectCamera: { [weak self] camera in self?.onSelectCamera(camera) }
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

    // MARK: - Zoom

    private func observeZoom() {
        zoomController.$scale
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshChrome() }
            .store(in: &cancellables)
    }

    private func handleHover(_ hovered: Bool) {
        hoverFadeOutTimer?.invalidate()
        if hovered {
            chromeVisible = true
            refreshChrome()
        } else {
            hoverFadeOutTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
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

    private func handlePlayerState(_ state: NativeCameraPlayer.State) {
        AppLog.rtsp.debug("PiPWindowController player state: \(String(describing: state), privacy: .public)")
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
        zoomController.viewDidResize()
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        persistence.saveFrame(window.frame)
        scheduleDragEndSnap()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        persistence.saveFrame(window.frame)
        zoomController.viewDidResize()
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

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

    private(set) var layout: PiPLayout = .single
    private var multiStreamController: MultiStreamController?
    private var stateCancellable: AnyCancellable?
    private let stateSubject = CurrentValueSubject<NativeCameraPlayer.State, Never>(.idle)

    // Single-mode aspect lock, enforced ourselves in `windowWillResize` rather than via
    // `NSWindow.contentAspectRatio` — toggling that native property to/from `.zero` when
    // entering/leaving multi-stream layouts crashed AppKit's live-resize geometry code
    // (NaN from an internal 0/0 ratio) on interactive window resize.
    private var lockedAspectRatio: CGFloat?

    // The multi layout we last switched away from (via a tile click or the layout
    // picker) — lets the single-view chrome offer a one-tap way back. Session-only,
    // not persisted; nil until the user has actually left a multi layout.
    private var lastMultiLayout: PiPLayout?

    // Exposed so StatusItemController can observe state. Re-piped from whichever mode
    // (single player or multi-stream controller) is active, so the subscriber set up
    // once at construction keeps working across layout switches.
    var playerStatePublisher: AnyPublisher<NativeCameraPlayer.State, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    // Camera list/selection for the in-viewer picker. Injected by AppDelegate, which owns
    // the camera list and the switch path (persist selection + restart stream). Defaults
    // are empty so the controller works standalone (e.g. in tests).
    var cameras: () -> [CameraConfig] = { [] }
    var selectedCameraName: () -> String? = { nil }
    var onSelectCamera: (CameraConfig) -> Void = { _ in }

    // Called by AppDelegate after a camera switch so the picker label refreshes.
    func refreshChromeForCameraChange() {
        refreshChrome()
        multiStreamController?.refreshForCameraListChange()
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
        hoverView.onClick = { [weak self] point in self?.handleWindowClick(point) }

        window.contentView = hoverView
        hoverView.addSubview(playerDrawableView)
        window.delegate = self

        installChrome()
        observeHover()
        observePlayerState()
        observeZoom()
        subscribeSingleModeState()

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
            let persistedLayout = self.persistence.loadLayout()
            if persistedLayout == .single {
                self.player.play(url: self.streamURL)
            } else {
                self.setLayout(persistedLayout)
            }
        }
    }

    func updateStreamURL(_ url: URL) {
        streamURL = url
        // Only restart playback if the single view is actually mounted; in a split/grid
        // layout this just remembers the camera to resume when the user switches back.
        guard layout == .single else { return }
        reconnectPolicy.reset()
        // Hide the video layer across the switch so the outgoing camera's last frame is
        // never shown re-zoomed to the incoming camera's level (the source of the flash).
        // Revealed again on the new camera's first decoded frame (.playing).
        setVideoHidden(true)
        player.stop()
        player.play(url: url)
        // Apply the new camera's saved zoom (or reset to 1×) while hidden.
        restoreZoomForCurrentCamera()
    }

    /// Instantly show/hide the video layer (no implicit fade). Opacity, not `isHidden`,
    /// so the display layer keeps decoding/enqueuing while hidden.
    private func setVideoHidden(_ hidden: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerDrawableView.displayLayer.opacity = hidden ? 0 : 1
        CATransaction.commit()
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
        multiStreamController?.stop()
    }

    // MARK: - Layout switching

    func setLayout(_ newLayout: PiPLayout) {
        guard newLayout != layout else { return }
        // Any explicit layout change (menu, in-chrome picker) drops the "quick return"
        // context — it only applies when `switchToSingleCamera` set it just below.
        lastMultiLayout = nil
        teardownCurrentLayoutContent()
        layout = newLayout
        persistence.saveLayout(newLayout)
        mountCurrentLayoutContent()
    }

    /// Jumps from a multi-stream layout straight to single view on the given camera —
    /// the destination of a plain click on one of the tiles. Unlike picking "Single
    /// Camera" from the layout menu, this remembers where we came from so single view
    /// can offer a one-tap way back.
    func switchToSingleCamera(_ camera: CameraConfig) {
        guard layout != .single else { return }
        let sourceLayout = layout
        onSelectCamera(camera)
        setLayout(.single)
        lastMultiLayout = sourceLayout
    }

    private func handleWindowClick(_ point: NSPoint) {
        guard layout != .single, let controller = multiStreamController else { return }
        guard let camera = controller.cameraForTile(at: point, containerSize: hoverView.bounds.size) else { return }
        switchToSingleCamera(camera)
    }

    private func teardownCurrentLayoutContent() {
        stateCancellable?.cancel()
        switch layout {
        case .single:
            reconnectTimer?.invalidate()
            videoSizeTimer?.invalidate()
            player.stop()
            setVideoHidden(true)
            playerDrawableView.removeFromSuperview()
            chromeHostingView.removeFromSuperview()
        case .split2, .grid4:
            multiStreamController?.stop()
            multiStreamController?.contentView.removeFromSuperview()
            multiStreamController = nil
        }
    }

    private func mountCurrentLayoutContent() {
        window.contentMinSize = layout.minWindowSize
        switch layout {
        case .single:
            // addSubview doesn't retroactively resize a view to the superview's current
            // bounds — autoresizingMask only kicks in on the *next* resize. Since these
            // views may have sat detached through an arbitrarily different window size
            // (multi layouts resize freely), sync their frame explicitly before re-adding.
            playerDrawableView.frame = hoverView.bounds
            chromeHostingView.frame = hoverView.bounds
            hoverView.addSubview(playerDrawableView)
            hoverView.addSubview(chromeHostingView)
            subscribeSingleModeState()
            reconnectPolicy.reset()
            setVideoHidden(true)
            player.play(url: streamURL)
            restoreZoomForCurrentCamera()
            refreshChrome()
        case .split2, .grid4:
            // Free-resize until a tile reports its camera's real video size (below).
            lockedAspectRatio = nil
            let controller = makeMultiStreamController(for: layout)
            multiStreamController = controller
            controller.contentView.frame = hoverView.bounds
            controller.contentView.autoresizingMask = [.width, .height]
            hoverView.addSubview(controller.contentView)
            subscribeMultiModeState(controller)
            controller.setChromeVisible(chromeVisible)
        }
    }

    private func makeMultiStreamController(for mode: PiPLayout) -> MultiStreamController {
        let controller = MultiStreamController(
            layout: mode,
            persistence: persistence,
            cameras: { [weak self] in self?.cameras() ?? [] },
            onClose: { [weak self] in self?.hideWindow() },
            onChangeLayout: { [weak self] newLayout in self?.setLayout(newLayout) }
        )
        controller.onAspectRatioChange = { [weak self] ratio in self?.lockAspectRatio(ratio) }
        return controller
    }

    private func subscribeSingleModeState() {
        stateCancellable = player.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.stateSubject.send(state) }
    }

    private func subscribeMultiModeState(_ controller: MultiStreamController) {
        stateCancellable = controller.statePublisher
            .sink { [weak self] state in self?.stateSubject.send(state) }
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
            onSelectCamera: { [weak self] camera in self?.onSelectCamera(camera) },
            onChangeLayout: { [weak self] layout in self?.setLayout(layout) },
            quickReturnLayout: lastMultiLayout
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
            applyChromeVisibility()
        } else {
            hoverFadeOutTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
                self?.chromeVisible = false
                self?.applyChromeVisibility()
            }
        }
    }

    private func applyChromeVisibility() {
        refreshChrome()
        multiStreamController?.setChromeVisible(chromeVisible)
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
            // The first frame's layout pass resets the backing layer's transform to
            // identity, so re-assert this camera's zoom NOW (post-reset) and only then
            // reveal — otherwise the new feed flashes at 1× before the zoom snaps in.
            restoreZoomForCurrentCamera()
            setVideoHidden(false)
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
        lockAspectRatio(size.height / size.width)
    }

    /// Locks live (drag-edge) resizing to `ratio` (height/width) via `windowWillResize`,
    /// and immediately snaps the current frame to match at the current width — used for
    /// the single camera's own ratio, and for the computed grid ratio in multi layouts.
    private func lockAspectRatio(_ ratio: CGFloat) {
        lockedAspectRatio = ratio
        let currentWidth = window.frame.width
        let targetHeight = (currentWidth * ratio).rounded()
        guard abs(targetHeight - window.frame.height) > 2 else { return }
        var newFrame = window.frame
        newFrame.size.height = targetHeight
        newFrame.origin.y = window.frame.maxY - targetHeight
        window.setFrame(newFrame, display: true, animate: true)
        persistence.saveFrame(newFrame)
        if layout == .single { zoomController.viewDidResize() }
    }

    // MARK: - NSWindowDelegate

    // Manually clamps interactive (drag-edge) resizes to `lockedAspectRatio` — the single
    // camera's own ratio in `.single`, or the computed grid ratio in multi layouts. Nil
    // (e.g. briefly after a layout switch, before a video size is known) resizes freely.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard let ratio = lockedAspectRatio else { return frameSize }
        var size = frameSize
        size.height = (size.width * ratio).rounded()
        return size
    }

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

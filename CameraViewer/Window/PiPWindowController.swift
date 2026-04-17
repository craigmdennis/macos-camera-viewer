import AppKit
import Combine
import SwiftUI

final class PiPWindowController: NSObject, NSWindowDelegate {
    let window: PiPWindow
    let player: CameraPlayer

    private let persistence: Persistence
    private let config: AppConfig
    private let hoverView: HoverTrackingView
    private var chromeHostingView: NSHostingView<ChromeOverlay>!
    private var reconnectPolicy = ReconnectPolicy()
    private var reconnectTimer: Timer?
    private var hoverFadeOutTimer: Timer?
    private var dragEndMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var chromeVisible = false

    // Exposed so StatusItemController can observe state.
    var playerStatePublisher: AnyPublisher<CameraPlayer.State, Never> {
        player.$state.eraseToAnyPublisher()
    }

    init(config: AppConfig, persistence: Persistence = Persistence()) {
        self.config = config
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

        self.player = CameraPlayer(drawable: hoverView, initiallyMuted: persistence.loadMuted())

        super.init()

        window.contentView = hoverView
        window.delegate = self

        installChrome()
        observeHover()
        observePlayerState()

        player.play(url: config.rtspsURL)
        window.setFrame(initialFrame, display: true)
        window.makeKeyAndOrderFront(nil)
    }

    deinit {
        reconnectTimer?.invalidate()
        hoverFadeOutTimer?.invalidate()
        if let monitor = dragEndMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

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
            onClose: { NSApp.terminate(nil) },
            onToggleMute: { [weak self] in self?.toggleMute() }
        )
    }

    private func refreshChrome() {
        chromeHostingView.rootView = currentOverlay()
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
        switch state {
        case .playing:
            reconnectPolicy.reset()
            reconnectTimer?.invalidate()
            lockAspectRatioToVideoSize()
        case .error:
            scheduleReconnect()
        case .idle, .opening, .buffering:
            break
        }
    }

    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        let delay = reconnectPolicy.recordFailure()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.player.play(url: self.config.rtspsURL)
        }
    }

    private func lockAspectRatioToVideoSize() {
        guard let size = player.videoSize, size.width > 0, size.height > 0 else { return }
        window.contentAspectRatio = size
    }

    // MARK: - NSWindowDelegate

    // windowDidMove fires per-pixel during drag; saving on every tick is wasteful but bounded
    // by UserDefaults' internal coalescing. windowDidEndLiveResize handles end-of-resize cleanly.
    // windowDidResize is intentionally NOT implemented — it duplicates windowDidEndLiveResize.

    func windowDidMove(_ notification: Notification) {
        persistence.saveFrame(window.frame)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        persistence.saveFrame(window.frame)
    }

    // Corner snap on drag-end. AppKit doesn't expose "window drag ended" directly —
    // windowDidMove fires continuously during drag — so we listen for leftMouseUp in this window.
    func installDragEndSnap() {
        dragEndMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            let screen = self.window.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
            let snapped = CornerSnap.snap(windowFrame: self.window.frame, screenVisibleFrame: screen)
            if snapped != self.window.frame {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    self.window.animator().setFrame(snapped, display: true)
                }
                self.persistence.saveFrame(snapped)
            }
            return event
        }
    }
}

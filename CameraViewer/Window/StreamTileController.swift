import AppKit
import Combine

/// One tile in a split/grid layout: a player + drawable view + its own reconnect loop,
/// fully independent of its siblings. Mirrors the reconnect logic in
/// `PiPWindowController` but scoped to a single stream, with no zoom/aspect-lock — tiles
/// just letterbox via `SampleBufferView`'s `.resizeAspect` gravity.
final class StreamTileController: NSObject {
    let drawableView: SampleBufferView
    let player: NativeCameraPlayer

    private(set) var camera: CameraConfig?
    private var reconnectPolicy = ReconnectPolicy()
    private var reconnectTimer: Timer?
    private var cancellable: AnyCancellable?

    var onStateChange: ((NativeCameraPlayer.State) -> Void)?

    override init() {
        let view = SampleBufferView(frame: .zero)
        self.drawableView = view
        self.player = NativeCameraPlayer(view: view, initiallyMuted: true)
        super.init()
        cancellable = player.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.handleState(state) }
    }

    func assign(_ camera: CameraConfig?) {
        self.camera = camera
        reconnectPolicy.reset()
        reconnectTimer?.invalidate()
        player.stop()
        guard let camera else { return }
        player.play(url: camera.uri)
    }

    func stop() {
        reconnectTimer?.invalidate()
        player.stop()
    }

    private func handleState(_ state: NativeCameraPlayer.State) {
        switch state {
        case .playing:
            reconnectPolicy.reset()
            reconnectTimer?.invalidate()
        case .error:
            scheduleReconnect()
        case .idle, .opening, .buffering:
            break
        }
        onStateChange?(state)
    }

    private func scheduleReconnect() {
        guard let camera else { return }
        reconnectTimer?.invalidate()
        let delay = reconnectPolicy.recordFailure()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.player.play(url: camera.uri)
        }
    }
}

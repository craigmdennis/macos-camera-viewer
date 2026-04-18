import AppKit
import Combine
import VLCKit

final class CameraPlayer: NSObject, VLCMediaPlayerDelegate {
    enum State: Equatable {
        case idle
        case opening
        case playing
        case buffering
        case error(message: String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isMuted: Bool

    private let player: VLCMediaPlayer

    init(drawable: NSView, initiallyMuted: Bool) {
        Self.configureVLCPluginPath()
        self.isMuted = initiallyMuted
        self.player = VLCMediaPlayer()
        super.init()
        Self.enableVerboseLogging()
        player.drawable = drawable
        player.delegate = self
        applyMute()
        NSLog("CameraPlayer: VLCKit version %@", VLCLibrary.shared().version)
    }

    // VLCKit's binary statically links libvlc but ships no codec plugins.
    // Point libvlc at /Applications/VLC.app's plugin directory at process startup.
    // Must run BEFORE any VLCMediaPlayer is constructed.
    private static let configureOnce: Void = {
        let candidates = [
            "/Applications/VLC.app/Contents/MacOS/plugins",
            "/Applications/VLC.app/Contents/Resources/plugins"
        ]
        if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            setenv("VLC_PLUGIN_PATH", found, 1)
            NSLog("CameraPlayer: VLC_PLUGIN_PATH=%@", found)
        } else {
            NSLog("CameraPlayer: VLC.app not found — install VLC.app from videolan.org for codec support.")
        }
    }()

    private static func configureVLCPluginPath() { _ = configureOnce }

    private static let enableLoggingOnce: Void = {
        VLCLibrary.shared().debugLogging = true
        VLCLibrary.shared().debugLoggingLevel = 4
    }()

    private static func enableVerboseLogging() { _ = enableLoggingOnce }

    var videoSize: CGSize? {
        let size = player.videoSize
        return size == .zero ? nil : size
    }

    func play(url: URL) {
        let media = VLCMedia(url: url)
        // Lower latency for live streams.
        media.addOption(":network-caching=300")
        media.addOption(":live-caching=300")
        player.media = media
        player.play()
    }

    func stop() {
        player.stop()
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        applyMute()
    }

    private func applyMute() {
        // VLCKit uses audio volume + mute flag; set both to be safe.
        player.audio?.isMuted = isMuted
    }

    // MARK: - VLCMediaPlayerDelegate

    func mediaPlayerStateChanged(_ notification: Notification) {
        // Capture state on the notification thread before hopping to main;
        // reading player.state inside the async block races with subsequent notifications.
        let vlcState = player.state
        NSLog("CameraPlayer: VLC state → %d", vlcState.rawValue)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch vlcState {
            case .opening:
                self.state = .opening
            case .buffering:
                self.state = .buffering
            case .playing:
                self.state = .playing
                self.applyMute()  // Re-apply; VLC occasionally resets mute when media changes.
            case .error:
                self.state = .error(message: "VLC reported an error")
            case .ended, .stopped:
                // Treat as error so the reconnect loop in PiPWindowController picks it up.
                self.state = .error(message: "stream ended")
            case .esAdded, .paused:
                break
            @unknown default:
                break
            }
        }
    }
}

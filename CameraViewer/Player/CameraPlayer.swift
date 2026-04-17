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

    private let player = VLCMediaPlayer()

    init(drawable: NSView, initiallyMuted: Bool) {
        self.isMuted = initiallyMuted
        super.init()
        player.drawable = drawable
        player.delegate = self
        applyMute()
    }

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
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch self.player.state {
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

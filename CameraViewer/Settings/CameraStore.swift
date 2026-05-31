import Foundation
import Combine

/// Observable owner of the camera list for the Settings UI. Edits write through to
/// config.json immediately (live-on-save) and publish so the rest of the app can react.
/// The single source of truth at runtime; `AppDelegate` observes `onChange` to refresh
/// the menu, the in-viewer picker, and the active stream.
final class CameraStore: ObservableObject {
    @Published private(set) var cameras: [CameraConfig]

    /// Fired after any successful mutation+save, with the new list. AppDelegate wires this
    /// to: update its loadedCameras, refresh menu/picker, and restart the stream if the
    /// active camera's URL changed or it was removed.
    var onChange: (([CameraConfig]) -> Void)?

    private let fileURL: URL

    init(cameras: [CameraConfig], fileURL: URL = AppConfigLoader.defaultFileURL) {
        self.cameras = cameras
        self.fileURL = fileURL
    }

    func add(name: String, uri: URL) {
        cameras.append(CameraConfig(name: name, uri: uri))
        persist()
    }

    func update(at index: Int, name: String, uri: URL) {
        guard cameras.indices.contains(index) else { return }
        cameras[index] = CameraConfig(name: name, uri: uri)
        persist()
    }

    func remove(at offsets: IndexSet) {
        cameras.remove(atOffsets: offsets)
        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        cameras.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    /// Replace the whole list without writing to disk — used when the app reloads config
    /// from disk itself (e.g. menu-bar Reconnect), so we don't echo a redundant save.
    func replaceAll(_ cameras: [CameraConfig]) {
        self.cameras = cameras
    }

    private func persist() {
        do {
            try AppConfigLoader.save(AppConfig(cameras: cameras), to: fileURL)
            onChange?(cameras)
        } catch {
            AppLog.config.error("Camera config save failed: \(String(describing: error))")
        }
    }
}

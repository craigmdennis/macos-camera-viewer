import AppKit
import Combine
import SwiftUI

/// Owns a split/grid PiP layout end-to-end: the tile players, their grid arrangement,
/// mute exclusivity (only one tile's audio at a time), per-tile camera persistence, and
/// a combined state for the menu-bar status line. `PiPWindowController` mounts
/// `contentView` in place of the single-stream view tree while a multi layout is active.
final class MultiStreamController: NSObject {
    let contentView: NSView
    let stateSubject = CurrentValueSubject<NativeCameraPlayer.State, Never>(.idle)

    // Fired with the ideal window height/width ratio once a reference tile's video size
    // is known, so the whole grid can be resize-locked to it (no letterboxing per tile).
    var onAspectRatioChange: ((CGFloat) -> Void)?

    private let gridView = TileGridView()
    private var chromeHostingView: NSHostingView<MultiChromeOverlay>!
    private var tiles: [StreamTileController] = []
    private var unmutedIndex: Int?
    private var chromeVisible = false
    private var aspectRatioPollTimer: Timer?

    private let layout: PiPLayout
    private let persistence: Persistence
    private let cameras: () -> [CameraConfig]
    private let onClose: () -> Void
    private let onChangeLayout: (PiPLayout) -> Void

    init(
        layout: PiPLayout,
        persistence: Persistence,
        cameras: @escaping () -> [CameraConfig],
        onClose: @escaping () -> Void,
        onChangeLayout: @escaping (PiPLayout) -> Void
    ) {
        self.layout = layout
        self.persistence = persistence
        self.cameras = cameras
        self.onClose = onClose
        self.onChangeLayout = onChangeLayout

        let container = NSView(frame: .zero)
        self.contentView = container
        super.init()

        gridView.frame = container.bounds
        gridView.autoresizingMask = [.width, .height]
        gridView.layoutMode = layout
        container.addSubview(gridView)

        buildTiles()

        let hosting = NSHostingView(rootView: makeOverlay())
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        container.addSubview(hosting)
        chromeHostingView = hosting
    }

    var statePublisher: AnyPublisher<NativeCameraPlayer.State, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    func stop() {
        aspectRatioPollTimer?.invalidate()
        tiles.forEach { $0.stop() }
    }

    func setChromeVisible(_ visible: Bool) {
        chromeVisible = visible
        refreshChrome()
    }

    /// The camera assigned to whichever tile contains `point` (AppKit coordinates,
    /// matching `TileGridView`'s own layout space), or nil if that tile is unassigned.
    /// Used to jump to single view on a plain click over a tile's video.
    func cameraForTile(at point: CGPoint, containerSize: CGSize) -> CameraConfig? {
        let frames = PiPLayout.frames(for: layout, containerSize: containerSize, spacing: TileGridView.spacing)
        guard let index = frames.firstIndex(where: { $0.contains(point) }), index < tiles.count else { return nil }
        return tiles[index].camera
    }

    /// Clears any tile pointing at a camera that no longer exists (renamed/removed
    /// in Settings) instead of leaving it stuck on a stale name.
    func refreshForCameraListChange() {
        let available = cameras()
        var changed = false
        for tile in tiles where tile.camera != nil {
            if !available.contains(where: { $0.name == tile.camera?.name }) {
                tile.assign(nil)
                changed = true
            }
        }
        if changed { persistAssignments() }
        refreshChrome()
    }

    // MARK: - Setup

    private func buildTiles() {
        let names = persistence.loadTileCameraNames(layout)
        let available = cameras()
        tiles = (0..<layout.tileCount).map { index in
            let tile = StreamTileController()
            tile.onStateChange = { [weak self] _ in
                self?.refreshCombinedState()
                self?.updateAspectRatioIfNeeded()
            }
            if let name = names[index], let camera = available.first(where: { $0.name == name }) {
                tile.assign(camera)
            }
            return tile
        }
        gridView.setTileViews(tiles.map { $0.drawableView })
        refreshCombinedState()
    }

    // MARK: - Grid aspect ratio

    /// Uses the first assigned tile with a known video size as the grid's reference
    /// aspect ratio — in practice all cameras on a given NVR share the same resolution,
    /// so any one of them is representative. Polls briefly if the size isn't in yet
    /// (mirrors the single-view `scheduleVideoSizeLock` pattern).
    private func updateAspectRatioIfNeeded() {
        guard let tile = tiles.first(where: { $0.camera != nil }) else { return }
        if let size = tile.player.videoSize, size.width > 0, size.height > 0 {
            aspectRatioPollTimer?.invalidate()
            onAspectRatioChange?(gridAspectRatio(forCameraRatio: size.height / size.width))
            return
        }
        aspectRatioPollTimer?.invalidate()
        aspectRatioPollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self, let tile = self.tiles.first(where: { $0.camera != nil }) else { timer.invalidate(); return }
            guard let size = tile.player.videoSize, size.width > 0, size.height > 0 else { return }
            timer.invalidate()
            self.onAspectRatioChange?(self.gridAspectRatio(forCameraRatio: size.height / size.width))
        }
    }

    /// Approximates the ideal window height/width ratio for `layout` given one camera's
    /// own ratio, ignoring the few points of inter-tile spacing (negligible at PiP sizes).
    private func gridAspectRatio(forCameraRatio cameraRatio: CGFloat) -> CGFloat {
        switch layout {
        case .single: return cameraRatio
        case .split2: return cameraRatio * 2
        case .grid4: return cameraRatio
        }
    }

    // MARK: - Mute exclusivity

    private func toggleMute(at index: Int) {
        if unmutedIndex == index {
            tiles[index].player.setMuted(true)
            unmutedIndex = nil
        } else {
            if let previous = unmutedIndex { tiles[previous].player.setMuted(true) }
            tiles[index].player.setMuted(false)
            unmutedIndex = index
        }
        refreshChrome()
    }

    // MARK: - Camera assignment

    private func selectCamera(_ camera: CameraConfig, at index: Int) {
        tiles[index].assign(camera)
        persistAssignments()
        updateAspectRatioIfNeeded()
        refreshChrome()
    }

    private func persistAssignments() {
        persistence.saveTileCameraNames(tiles.map { $0.camera?.name }, layout: layout)
    }

    // MARK: - Combined state for the menu-bar status line

    private func refreshCombinedState() {
        let assignedStates = tiles.compactMap { $0.camera != nil ? $0.player.state : nil }
        if assignedStates.contains(.playing) {
            stateSubject.send(.playing)
        } else if assignedStates.isEmpty {
            stateSubject.send(.idle)
        } else if assignedStates.allSatisfy(Self.isError) {
            stateSubject.send(.error(message: "All cameras disconnected"))
        } else {
            stateSubject.send(.opening)
        }
    }

    private static func isError(_ state: NativeCameraPlayer.State) -> Bool {
        if case .error = state { return true }
        return false
    }

    // MARK: - Chrome

    private func refreshChrome() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.chromeHostingView.rootView = self.makeOverlay()
        }
    }

    private func makeOverlay() -> MultiChromeOverlay {
        let tileModels = tiles.map { tile in
            TileViewModel(
                camera: tile.camera,
                isMuted: tile.player.isMuted,
                isLoading: tile.camera != nil && tile.player.state != .playing
            )
        }
        return MultiChromeOverlay(
            isVisible: chromeVisible,
            layout: layout,
            tiles: tileModels,
            allCameras: cameras(),
            onClose: onClose,
            onChangeLayout: onChangeLayout,
            onSelectCamera: { [weak self] index, camera in self?.selectCamera(camera, at: index) },
            onToggleMute: { [weak self] index in self?.toggleMute(at: index) }
        )
    }
}

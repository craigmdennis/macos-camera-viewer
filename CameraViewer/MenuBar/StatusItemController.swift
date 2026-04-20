import AppKit
import Combine

final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let onReconnect: () -> Void
    private let onToggleVisibility: () -> Void
    private let isWindowVisible: () -> Bool
    private let cameras: () -> [CameraConfig]
    private let selectedCameraName: () -> String?
    private let onSelectCamera: (CameraConfig) -> Void
    private var cancellables = Set<AnyCancellable>()
    private var lastErrorItem: NSMenuItem?
    private var lastErrorAt: Date?
    private var showHideItem: NSMenuItem!
    private var camerasSubmenuItem: NSMenuItem!

    init(
        statePublisher: AnyPublisher<CameraPlayer.State, Never>,
        onReconnect: @escaping () -> Void,
        onToggleVisibility: @escaping () -> Void,
        isWindowVisible: @escaping () -> Bool,
        cameras: @escaping () -> [CameraConfig],
        selectedCameraName: @escaping () -> String?,
        onSelectCamera: @escaping (CameraConfig) -> Void
    ) {
        self.onReconnect = onReconnect
        self.onToggleVisibility = onToggleVisibility
        self.isWindowVisible = isWindowVisible
        self.cameras = cameras
        self.selectedCameraName = selectedCameraName
        self.onSelectCamera = onSelectCamera
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let button = statusItem.button
        button?.image = NSImage(systemSymbolName: "video.fill", accessibilityDescription: "Camera Viewer")
        button?.image?.isTemplate = true

        buildMenu()

        statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.handleState(state) }
            .store(in: &cancellables)
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        showHideItem = NSMenuItem(title: "Hide Camera", action: #selector(toggleVisibility), keyEquivalent: "")
        showHideItem.target = self
        menu.addItem(showHideItem)

        menu.addItem(.separator())

        camerasSubmenuItem = NSMenuItem(title: "Cameras", action: nil, keyEquivalent: "")
        camerasSubmenuItem.submenu = NSMenu(title: "Cameras")
        menu.addItem(camerasSubmenuItem)

        menu.addItem(.separator())

        let reveal = NSMenuItem(title: "Reveal Config in Finder", action: #selector(revealConfig), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)

        let reconnectItem = NSMenuItem(title: "Reconnect", action: #selector(reconnect), keyEquivalent: "")
        reconnectItem.target = self
        menu.addItem(reconnectItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        showHideItem.title = isWindowVisible() ? "Hide Camera" : "Show Camera"
        rebuildCamerasSubmenu()
    }

    private func rebuildCamerasSubmenu() {
        let submenu = camerasSubmenuItem.submenu!
        submenu.removeAllItems()
        let currentName = selectedCameraName()
        for camera in cameras() {
            let item = NSMenuItem(title: camera.name, action: #selector(selectCamera(_:)), keyEquivalent: "")
            item.target = self
            item.state = camera.name == currentName ? .on : .off
            item.representedObject = camera
            submenu.addItem(item)
        }
    }

    private func handleState(_ state: CameraPlayer.State) {
        switch state {
        case .playing:
            statusItem.button?.image = NSImage(systemSymbolName: "video.fill", accessibilityDescription: "Playing")
            statusItem.button?.image?.isTemplate = true
            lastErrorAt = nil
            if let item = lastErrorItem {
                statusItem.menu?.removeItem(item)
                lastErrorItem = nil
            }
        case .error(let message):
            statusItem.button?.image = NSImage(systemSymbolName: "video.slash.fill", accessibilityDescription: "Error")
            statusItem.button?.image?.isTemplate = true
            noteError(message)
        case .idle, .opening, .buffering:
            break
        }
    }

    private func noteError(_ message: String) {
        let now = Date()
        if lastErrorAt == nil { lastErrorAt = now }
        guard let since = lastErrorAt, now.timeIntervalSince(since) >= 30 else { return }
        guard let menu = statusItem.menu else { return }
        let title = "Last error: \(message)"
        if let item = lastErrorItem {
            item.title = title
        } else {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.insertItem(item, at: 0)
            menu.insertItem(.separator(), at: 1)
            lastErrorItem = item
        }
    }

    @objc private func revealConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([AppConfigLoader.defaultFileURL])
    }

    @objc private func reconnect() {
        onReconnect()
    }

    @objc private func toggleVisibility() {
        onToggleVisibility()
    }

    @objc private func selectCamera(_ sender: NSMenuItem) {
        guard let camera = sender.representedObject as? CameraConfig else { return }
        onSelectCamera(camera)
    }
}

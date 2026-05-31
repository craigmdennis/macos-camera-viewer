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
    private let onOpenSettings: () -> Void
    private var cancellables = Set<AnyCancellable>()
    private var statusLineItem: NSMenuItem!
    private var currentState: NativeCameraPlayer.State = .idle
    private var showHideItem: NSMenuItem!
    private var camerasSubmenuItem: NSMenuItem!

    init(
        statePublisher: AnyPublisher<NativeCameraPlayer.State, Never>,
        onReconnect: @escaping () -> Void,
        onToggleVisibility: @escaping () -> Void,
        isWindowVisible: @escaping () -> Bool,
        cameras: @escaping () -> [CameraConfig],
        selectedCameraName: @escaping () -> String?,
        onSelectCamera: @escaping (CameraConfig) -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.onReconnect = onReconnect
        self.onToggleVisibility = onToggleVisibility
        self.isWindowVisible = isWindowVisible
        self.cameras = cameras
        self.selectedCameraName = selectedCameraName
        self.onSelectCamera = onSelectCamera
        self.onOpenSettings = onOpenSettings
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

        // Live status line: always reflects the player's current state, including the
        // exact failure reason when a stream can't connect.
        statusLineItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusLineItem.isEnabled = false
        menu.addItem(statusLineItem)
        menu.addItem(.separator())

        showHideItem = NSMenuItem(title: "Hide Camera", action: #selector(toggleVisibility), keyEquivalent: "")
        showHideItem.target = self
        menu.addItem(showHideItem)

        menu.addItem(.separator())

        camerasSubmenuItem = NSMenuItem(title: "Cameras", action: nil, keyEquivalent: "")
        camerasSubmenuItem.submenu = NSMenu(title: "Cameras")
        menu.addItem(camerasSubmenuItem)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let reconnectItem = NSMenuItem(title: "Reconnect", action: #selector(reconnect), keyEquivalent: "")
        reconnectItem.target = self
        menu.addItem(reconnectItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        showHideItem.title = isWindowVisible() ? "Hide Camera" : "Show Camera"
        statusLineItem.title = statusDescription(currentState)
        rebuildCamerasSubmenu()
    }

    private func statusDescription(_ state: NativeCameraPlayer.State) -> String {
        switch state {
        case .idle:      return "Idle"
        case .opening:   return "Connecting…"
        case .buffering: return "Buffering…"
        case .playing:   return "● Playing"
        case .error(let message): return "⚠ \(message)"
        }
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

    private func handleState(_ state: NativeCameraPlayer.State) {
        currentState = state
        // Keep the menu-bar glyph in sync; the live status line (refreshed on open)
        // carries the detail, including the failure message.
        let symbol: String
        switch state {
        case .playing:                  symbol = "video.fill"
        case .error:                    symbol = "video.slash.fill"
        case .idle, .opening, .buffering: symbol = "video.fill"
        }
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: statusDescription(state))
        statusItem.button?.image?.isTemplate = true
        // If the menu is already open, update the line immediately.
        statusLineItem?.title = statusDescription(state)
    }

    @objc private func openSettings() {
        onOpenSettings()
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

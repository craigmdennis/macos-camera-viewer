import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: PiPWindowController?
    private var statusItemController: StatusItemController?
    private var settingsWindowController: SettingsWindowController?
    private var store: CameraStore!
    private var activeCamera: CameraConfig?
    private let persistence = Persistence()

    private var loadedCameras: [CameraConfig] { store?.cameras ?? [] }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let config: AppConfig
        do {
            config = try AppConfigLoader.load()
        } catch AppConfigError.fileNotFound {
            // No config yet → onboarding owns first launch (build the store empty).
            store = CameraStore(cameras: [])
            startOnboarding()
            return
        } catch AppConfigError.malformed(let underlying) {
            presentMalformedAlert(underlying: underlying)
            NSApp.terminate(nil)
            return
        } catch {
            presentMalformedAlert(underlying: error)
            NSApp.terminate(nil)
            return
        }

        store = CameraStore(cameras: config.cameras)
        store.onChange = { [weak self] cameras in self?.handleCameraListChange(cameras) }

        let savedName = persistence.loadSelectedCameraName()
        let camera = config.cameras.first(where: { $0.name == savedName }) ?? config.cameras[0]
        activeCamera = camera
        persistence.saveSelectedCameraName(camera.name)

        startViewer(initial: camera)
    }

    private func startViewer(initial camera: CameraConfig) {
        let controller = PiPWindowController(streamURL: camera.uri, persistence: persistence)
        controller.installDragEndSnap()
        windowController = controller

        statusItemController = StatusItemController(
            statePublisher: controller.playerStatePublisher,
            onReconnect: { [weak self, weak controller] in
                guard let self, let controller else { return }
                let reloaded = (try? AppConfigLoader.load()) ?? AppConfig(cameras: self.loadedCameras)
                self.store.replaceAll(reloaded.cameras)
                let currentName = self.activeCamera?.name
                guard let target = reloaded.cameras.first(where: { $0.name == currentName })
                                    ?? reloaded.cameras.first else { return }
                self.activeCamera = target
                self.persistence.saveSelectedCameraName(target.name)
                controller.updateStreamURL(target.uri)
            },
            onToggleVisibility: { [weak controller] in
                guard let controller else { return }
                controller.isWindowVisible ? controller.hideWindow() : controller.showWindow()
            },
            isWindowVisible: { [weak controller] in controller?.isWindowVisible ?? false },
            cameras: { [weak self] in self?.loadedCameras ?? [] },
            selectedCameraName: { [weak self] in self?.activeCamera?.name },
            onSelectCamera: { [weak self] camera in self?.selectCamera(camera) },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )

        // Feed the in-viewer picker the same camera data + switch path as the menu bar.
        controller.cameras = { [weak self] in self?.loadedCameras ?? [] }
        controller.selectedCameraName = { [weak self] in self?.activeCamera?.name }
        controller.onSelectCamera = { [weak self] camera in self?.selectCamera(camera) }
    }

    // MARK: - Camera selection / list changes

    /// Single switch path shared by menu-bar submenu and in-viewer picker.
    private func selectCamera(_ camera: CameraConfig) {
        guard camera.name != activeCamera?.name else { return }
        activeCamera = camera
        persistence.saveSelectedCameraName(camera.name)
        windowController?.updateStreamURL(camera.uri)
        windowController?.refreshChromeForCameraChange()
    }

    /// Live-on-save reaction from the Settings UI: refresh menu/picker and, if the active
    /// camera's URL changed or it was removed, restart the stream.
    private func handleCameraListChange(_ cameras: [CameraConfig]) {
        if windowController == nil, let first = cameras.first {
            // First camera added during onboarding → start the viewer now.
            activeCamera = first
            persistence.saveSelectedCameraName(first.name)
            startViewer(initial: first)
            return
        }

        let activeName = activeCamera?.name
        if let stillThere = cameras.first(where: { $0.name == activeName }) {
            if stillThere.uri != activeCamera?.uri {       // URL edited under us
                activeCamera = stillThere
                windowController?.updateStreamURL(stillThere.uri)
            }
        } else if let fallback = cameras.first {           // active camera removed
            selectCamera(fallback)
        }
        windowController?.refreshChromeForCameraChange()
    }

    // MARK: - Settings / onboarding

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(store: store)
        }
        settingsWindowController?.show()
    }

    private func startOnboarding() {
        store.onChange = { [weak self] cameras in self?.handleCameraListChange(cameras) }
        let controller = OnboardingWindowController(store: store)
        settingsWindowController = nil
        onboardingWindowController = controller
        controller.show()
    }

    private var onboardingWindowController: OnboardingWindowController?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func presentMalformedAlert(underlying: Error) {
        let alert = NSAlert()
        alert.messageText = "Camera Viewer could not read its config file."
        alert.informativeText = """
        Details: \(underlying.localizedDescription)

        Path: \(AppConfigLoader.defaultFileURL.path)

        Expected format:
        { "cameras": [{ "name": "…", "uri": "rtsps://…" }] }
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

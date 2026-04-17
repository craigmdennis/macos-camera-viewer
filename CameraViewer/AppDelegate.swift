import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: PiPWindowController?
    private var statusItemController: StatusItemController?
    private let streamProxy = StreamProxy()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let config: AppConfig
        do {
            config = try AppConfigLoader.load()
        } catch AppConfigError.fileNotFound(let path) {
            try? AppConfigLoader.writeStub(to: path)
            presentFirstLaunchAlert(path: path)
            openConfigInTextEdit(path)
            NSApp.terminate(nil)
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

        do {
            try streamProxy.start(upstream: config.rtspsURL)
        } catch {
            presentProxyFailureAlert(underlying: error)
            NSApp.terminate(nil)
            return
        }

        let controller = PiPWindowController(streamURL: StreamProxy.localURL)
        controller.installDragEndSnap()
        windowController = controller

        statusItemController = StatusItemController(
            statePublisher: controller.playerStatePublisher,
            onReconnect: { [weak self, weak controller] in
                guard let self, let controller else { return }
                let upstream = (try? AppConfigLoader.load().rtspsURL) ?? config.rtspsURL
                do {
                    try self.streamProxy.start(upstream: upstream)
                } catch {
                    NSLog("Reconnect: proxy restart failed: %@", String(describing: error))
                }
                controller.updateStreamURL(StreamProxy.localURL)
            },
            onToggleVisibility: { [weak controller] in
                guard let controller else { return }
                if controller.isWindowVisible {
                    controller.hideWindow()
                } else {
                    controller.showWindow()
                }
            },
            isWindowVisible: { [weak controller] in
                controller?.isWindowVisible ?? false
            }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        streamProxy.stop()
    }

    private func openConfigInTextEdit(_ path: URL) {
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open(
            [path],
            withApplicationAt: textEdit,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func presentFirstLaunchAlert(path: URL) {
        let alert = NSAlert()
        alert.messageText = "Camera Viewer needs a camera URL."
        alert.informativeText = """
        A template config file has been created at:
        \(path.path)

        Open it, replace the placeholder RTSPS URL with your camera's URL (Protect web UI → Settings → Advanced → RTSP), save, and launch Camera Viewer again.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentMalformedAlert(underlying: Error) {
        let alert = NSAlert()
        alert.messageText = "Camera Viewer could not read its config file."
        alert.informativeText = "Details: \(underlying.localizedDescription)\n\nPath: \(AppConfigLoader.defaultFileURL.path)"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentProxyFailureAlert(underlying: Error) {
        let alert = NSAlert()
        alert.messageText = "Camera Viewer could not start its stream proxy."
        alert.informativeText = "Details: \(String(describing: underlying))"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

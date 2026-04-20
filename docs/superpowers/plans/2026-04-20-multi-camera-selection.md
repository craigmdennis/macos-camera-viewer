# Multi-Camera Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single-URL config with a named camera array, add a Cameras submenu to the menu bar, and persist the last selected camera across launches.

**Architecture:** `AppConfig` gains a `cameras: [CameraConfig]` array; `Persistence` stores the selected camera name; `StatusItemController` builds a Cameras submenu rebuilt on every menu open; `AppDelegate` resolves the active camera at launch and wires the selection callback through `StreamProxy` + `PiPWindowController`.

**Tech Stack:** Swift, AppKit, Combine, XCTest, VLCKit (unchanged), go2rtc subprocess (unchanged).

---

## File Map

| File | Change |
|------|--------|
| `CameraViewer/Config/AppConfig.swift` | Add `CameraConfig` struct; replace `rtspsURL` with `cameras: [CameraConfig]`; add empty-array validation in `load()` |
| `CameraViewer/Config/Persistence.swift` | Add `selectedCameraName` load/save |
| `CameraViewer/MenuBar/StatusItemController.swift` | Add three new closures; add Cameras submenu; rebuild submenu in `menuWillOpen` |
| `CameraViewer/AppDelegate.swift` | Resolve active camera on launch; wire `onSelectCamera` callback |
| `CameraViewerTests/AppConfigTests.swift` | Full rewrite — all existing tests reference old `rtspsURL`; add new tests |
| `CameraViewerTests/PersistenceTests.swift` | Add two new tests for `selectedCameraName` |

---

## Task 1: Update AppConfig (data model + tests)

**Files:**
- Modify: `CameraViewer/Config/AppConfig.swift`
- Modify: `CameraViewerTests/AppConfigTests.swift`

- [ ] **Step 1: Replace `AppConfigTests.swift` with updated tests**

The entire file changes because every existing test references `rtspsURL`. Write this as the new file:

```swift
import XCTest
@testable import CameraViewer

final class AppConfigTests: XCTestCase {
    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testRoundTripEncodeDecode() throws {
        let original = AppConfig(cameras: [
            CameraConfig(name: "Front Door", uri: URL(string: "rtsps://10.0.0.1:7441/abc?enableSrtp")!)
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testDecodeIgnoresUnknownKeys() throws {
        let json = #"""
        {
          "_comment": "hello",
          "cameras": [
            { "name": "Front Door", "uri": "rtsps://10.0.0.1:7441/abc?enableSrtp" }
          ]
        }
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(decoded.cameras.count, 1)
        XCTAssertEqual(decoded.cameras[0].name, "Front Door")
        XCTAssertEqual(decoded.cameras[0].uri.absoluteString, "rtsps://10.0.0.1:7441/abc?enableSrtp")
    }

    func testLoadThrowsFileNotFoundWhenMissing() {
        let missing = tmpDir.appendingPathComponent("nope.json")
        XCTAssertThrowsError(try AppConfigLoader.load(from: missing)) { error in
            guard case AppConfigError.fileNotFound = error else {
                return XCTFail("expected fileNotFound, got \(error)")
            }
        }
    }

    func testLoadThrowsMalformedOnBadJSON() throws {
        let url = tmpDir.appendingPathComponent("bad.json")
        try "{ not json }".data(using: .utf8)!.write(to: url)
        XCTAssertThrowsError(try AppConfigLoader.load(from: url)) { error in
            guard case AppConfigError.malformed = error else {
                return XCTFail("expected malformed, got \(error)")
            }
        }
    }

    func testLoadThrowsMalformedOnEmptyCamerasArray() throws {
        let url = tmpDir.appendingPathComponent("empty.json")
        try #"{ "cameras": [] }"#.data(using: .utf8)!.write(to: url)
        XCTAssertThrowsError(try AppConfigLoader.load(from: url)) { error in
            guard case AppConfigError.malformed = error else {
                return XCTFail("expected malformed, got \(error)")
            }
        }
    }

    func testLoadThrowsMalformedOnOldRtspsURLFormat() throws {
        let url = tmpDir.appendingPathComponent("old.json")
        try #"{ "rtspsURL": "rtsps://10.0.0.1:7441/abc?enableSrtp" }"#.data(using: .utf8)!.write(to: url)
        XCTAssertThrowsError(try AppConfigLoader.load(from: url)) { error in
            guard case AppConfigError.malformed = error else {
                return XCTFail("expected malformed, got \(error)")
            }
        }
    }

    func testWriteStubCreatesDirectoryAndValidJSON() throws {
        let url = tmpDir
            .appendingPathComponent("sub", isDirectory: true)
            .appendingPathComponent("config.json")
        try AppConfigLoader.writeStub(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let reloaded = try AppConfigLoader.load(from: url)
        XCTAssertFalse(reloaded.cameras.isEmpty)
        XCTAssertEqual(reloaded.cameras[0].uri.scheme, "rtsps")
    }
}
```

- [ ] **Step 2: Run tests — expect build failure (rtspsURL no longer exists once we update the model)**

```bash
xcodebuild test -project CameraViewer.xcodeproj -scheme CameraViewer -destination 'platform=macOS' 2>&1 | grep -E "(error:|warning:|PASSED|FAILED|Build)"
```

Expected: compile error — `AppConfig` still has `rtspsURL`, new tests reference `cameras`.

- [ ] **Step 3: Replace `AppConfig.swift` with the new model**

```swift
import Foundation

struct CameraConfig: Codable, Equatable {
    var name: String
    var uri: URL
}

struct AppConfig: Codable, Equatable {
    var cameras: [CameraConfig]
}

enum AppConfigError: Error {
    case fileNotFound(path: URL)
    case malformed(underlying: Error)
}

enum AppConfigLoader {
    static let fileName = "config.json"
    static let appSupportFolderName = "CameraViewer"

    static var defaultDirectoryURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(appSupportFolderName, isDirectory: true)
    }

    static var defaultFileURL: URL {
        defaultDirectoryURL.appendingPathComponent(fileName)
    }

    static func load(from url: URL = defaultFileURL) throws -> AppConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AppConfigError.fileNotFound(path: url)
        }
        let data = try Data(contentsOf: url)
        do {
            let config = try JSONDecoder().decode(AppConfig.self, from: data)
            guard !config.cameras.isEmpty else {
                throw AppConfigError.malformed(underlying: NSError(
                    domain: "AppConfig", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "cameras array must not be empty"]
                ))
            }
            return config
        } catch let appErr as AppConfigError {
            throw appErr
        } catch {
            throw AppConfigError.malformed(underlying: error)
        }
    }

    static func writeStub(to url: URL = defaultFileURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let stub = """
        {
          "_comment": "Add your cameras below. Find RTSPS URLs in Protect web UI → Settings → Advanced → RTSP.",
          "cameras": [
            { "name": "Front Door", "uri": "rtsps://10.0.0.1:7441/YOUR_CAMERA_ID_1?enableSrtp" },
            { "name": "Back Yard",  "uri": "rtsps://10.0.0.1:7441/YOUR_CAMERA_ID_2?enableSrtp" }
          ]
        }

        """
        try Data(stub.utf8).write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 4: Run tests — expect AppConfigTests to pass, AppDelegate to fail to compile**

```bash
xcodebuild test -project CameraViewer.xcodeproj -scheme CameraViewer -destination 'platform=macOS' 2>&1 | grep -E "(error:|AppConfigTests|PASSED|FAILED)"
```

Expected: `AppConfigTests` all pass; `AppDelegate.swift` compile errors referencing `config.rtspsURL` (will be fixed in Task 4).

- [ ] **Step 5: Commit**

```bash
git add CameraViewer/Config/AppConfig.swift CameraViewerTests/AppConfigTests.swift
git commit -m "feat: update AppConfig to cameras array with CameraConfig"
```

---

## Task 2: Update Persistence (selectedCameraName)

**Files:**
- Modify: `CameraViewer/Config/Persistence.swift`
- Modify: `CameraViewerTests/PersistenceTests.swift`

- [ ] **Step 1: Add two new tests to `PersistenceTests.swift`**

Append inside the `PersistenceTests` class, before the closing `}`:

```swift
    func testLoadSelectedCameraNameReturnsNilWhenUnset() {
        let p = Persistence(defaults: defaults)
        XCTAssertNil(p.loadSelectedCameraName())
    }

    func testRoundTripSelectedCameraName() {
        let p = Persistence(defaults: defaults)
        p.saveSelectedCameraName("Front Door")
        XCTAssertEqual(p.loadSelectedCameraName(), "Front Door")
        p.saveSelectedCameraName("Back Yard")
        XCTAssertEqual(p.loadSelectedCameraName(), "Back Yard")
    }
```

- [ ] **Step 2: Run tests — expect failure**

```bash
xcodebuild test -project CameraViewer.xcodeproj -scheme CameraViewer -destination 'platform=macOS' 2>&1 | grep -E "(PersistenceTests|error:|PASSED|FAILED)"
```

Expected: `testLoadSelectedCameraNameReturnsNilWhenUnset` and `testRoundTripSelectedCameraName` fail — method not found.

- [ ] **Step 3: Update `Persistence.swift` to add the new key and methods**

```swift
import Foundation
import AppKit

struct Persistence {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let windowFrame = "windowFrame"
        static let isMuted = "isMuted"
        static let selectedCameraName = "selectedCameraName"
    }

    func loadFrame() -> NSRect? {
        guard let string = defaults.string(forKey: Key.windowFrame) else { return nil }
        let rect = NSRectFromString(string)
        return rect == .zero ? nil : rect
    }

    func saveFrame(_ rect: NSRect) {
        defaults.set(NSStringFromRect(rect), forKey: Key.windowFrame)
    }

    func loadMuted() -> Bool {
        defaults.object(forKey: Key.isMuted) as? Bool ?? true
    }

    func saveMuted(_ muted: Bool) {
        defaults.set(muted, forKey: Key.isMuted)
    }

    func loadSelectedCameraName() -> String? {
        defaults.string(forKey: Key.selectedCameraName)
    }

    func saveSelectedCameraName(_ name: String) {
        defaults.set(name, forKey: Key.selectedCameraName)
    }
}
```

- [ ] **Step 4: Run tests — expect all Persistence tests to pass**

```bash
xcodebuild test -project CameraViewer.xcodeproj -scheme CameraViewer -destination 'platform=macOS' 2>&1 | grep -E "(PersistenceTests|PASSED|FAILED)"
```

Expected: all `PersistenceTests` pass.

- [ ] **Step 5: Commit**

```bash
git add CameraViewer/Config/Persistence.swift CameraViewerTests/PersistenceTests.swift
git commit -m "feat: add selectedCameraName persistence"
```

---

## Task 3: Update StatusItemController (Cameras submenu)

**Files:**
- Modify: `CameraViewer/MenuBar/StatusItemController.swift`

No unit tests for this file (AppKit menu code — consistent with existing project pattern).

- [ ] **Step 1: Replace `StatusItemController.swift` with the updated version**

```swift
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
```

- [ ] **Step 2: Build to verify no compile errors (tests may still fail due to AppDelegate)**

```bash
xcodebuild build -project CameraViewer.xcodeproj -scheme CameraViewer -destination 'platform=macOS' 2>&1 | grep -E "(error:|Build succeeded|Build FAILED)"
```

Expected: compile errors in `AppDelegate.swift` only (StatusItemController init signature changed). That's fine — fixed in the next task.

- [ ] **Step 3: Commit**

```bash
git add CameraViewer/MenuBar/StatusItemController.swift
git commit -m "feat: add Cameras submenu to status item controller"
```

---

## Task 4: Update AppDelegate (wire everything together)

**Files:**
- Modify: `CameraViewer/AppDelegate.swift`

- [ ] **Step 1: Replace `AppDelegate.swift` with the updated version**

Key changes:
- Resolve active camera from the persisted name (fallback to index 0).
- Pass `cameras`, `selectedCameraName`, and `onSelectCamera` closures to `StatusItemController`.
- In `onSelectCamera`: persist the name, restart the proxy, update the window controller.
- Update error alert text to mention the new config format.

```swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: PiPWindowController?
    private var statusItemController: StatusItemController?
    private let streamProxy = StreamProxy()
    private var activeCamera: CameraConfig?
    private var loadedCameras: [CameraConfig] = []
    private let persistence = Persistence()

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

        loadedCameras = config.cameras

        let savedName = persistence.loadSelectedCameraName()
        let camera = config.cameras.first(where: { $0.name == savedName }) ?? config.cameras[0]
        activeCamera = camera
        persistence.saveSelectedCameraName(camera.name)

        do {
            try streamProxy.start(upstream: camera.uri)
        } catch {
            presentProxyFailureAlert(underlying: error)
            NSApp.terminate(nil)
            return
        }

        let controller = PiPWindowController(streamURL: StreamProxy.localURL, persistence: persistence)
        controller.installDragEndSnap()
        windowController = controller

        statusItemController = StatusItemController(
            statePublisher: controller.playerStatePublisher,
            onReconnect: { [weak self, weak controller] in
                guard let self, let controller else { return }
                let reloadedConfig = (try? AppConfigLoader.load()) ?? AppConfig(cameras: self.loadedCameras)
                self.loadedCameras = reloadedConfig.cameras
                let currentName = self.activeCamera?.name
                let target = reloadedConfig.cameras.first(where: { $0.name == currentName }) ?? reloadedConfig.cameras[0]
                self.activeCamera = target
                self.persistence.saveSelectedCameraName(target.name)
                do {
                    try self.streamProxy.start(upstream: target.uri)
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
            },
            cameras: { [weak self] in
                self?.loadedCameras ?? []
            },
            selectedCameraName: { [weak self] in
                self?.activeCamera?.name
            },
            onSelectCamera: { [weak self, weak controller] camera in
                guard let self, let controller else { return }
                self.activeCamera = camera
                self.persistence.saveSelectedCameraName(camera.name)
                do {
                    try self.streamProxy.start(upstream: camera.uri)
                } catch {
                    NSLog("Camera switch: proxy restart failed: %@", String(describing: error))
                }
                controller.updateStreamURL(StreamProxy.localURL)
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

        Open it, replace the placeholder RTSPS URLs with your camera URLs (Protect web UI → Settings → Advanced → RTSP), save, and launch Camera Viewer again.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentMalformedAlert(underlying: Error) {
        let alert = NSAlert()
        alert.messageText = "Camera Viewer could not read its config file."
        alert.informativeText = """
        Details: \(underlying.localizedDescription)

        Path: \(AppConfigLoader.defaultFileURL.path)

        The config format has changed. Expected:
        { "cameras": [{ "name": "…", "uri": "rtsps://…" }] }
        """
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
```

- [ ] **Step 2: Run all tests — expect full pass**

```bash
xcodebuild test -project CameraViewer.xcodeproj -scheme CameraViewer -destination 'platform=macOS' 2>&1 | grep -E "(error:|PASSED|FAILED|Build succeeded|Build FAILED)"
```

Expected: Build succeeded, all tests pass.

- [ ] **Step 3: Commit**

```bash
git add CameraViewer/AppDelegate.swift
git commit -m "feat: wire multi-camera selection in AppDelegate"
```

---

## Task 5: Update config.example.json

**Files:**
- Modify: `config.example.json` (if it exists in the repo root)

- [ ] **Step 1: Check if config.example.json exists and update it**

```bash
cat config.example.json
```

If it exists, replace its contents with:

```json
{
  "_comment": "Add your cameras below. Find RTSPS URLs in Protect web UI → Settings → Advanced → RTSP.",
  "cameras": [
    { "name": "Front Door", "uri": "rtsps://10.0.0.1:7441/YOUR_CAMERA_ID_1?enableSrtp" },
    { "name": "Back Yard",  "uri": "rtsps://10.0.0.1:7441/YOUR_CAMERA_ID_2?enableSrtp" }
  ]
}
```

- [ ] **Step 2: Commit**

```bash
git add config.example.json
git commit -m "docs: update config.example.json to multi-camera format"
```

# macOS Camera Viewer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A single-window macOS app that displays a local Unifi Protect RTSPS camera feed as a Picture-in-Picture–style floating window — above every app, across all Spaces, with hover-only chrome (close + mute), corner-snap drag, and aspect-locked corner resize.

**Architecture:** AppKit shell (`NSWindow` subclass, menu-bar status item) with SwiftUI chrome overlay via `NSHostingView`. VLCKit handles RTSPS playback. State is small: one config file on disk (JSON), two `UserDefaults` keys (frame + mute), and Combine-published player state. Pure modules — `CornerSnap`, `ReconnectPolicy`, `AppConfig` codec — are unit-tested TDD-style; AppKit integration is verified by a manual smoke-test checklist.

**Tech Stack:** Swift 5.10+, macOS 13+, AppKit + SwiftUI, VLCKit 3.7.3 (prebuilt xcframework from artifacts.videolan.org, fetched by `scripts/bootstrap.sh` into gitignored `Frameworks/`), XCTest. Project file generated from YAML via `xcodegen` so the repo stays diff-friendly.

**Spec:** `docs/superpowers/specs/2026-04-17-macos-camera-viewer-design.md`

---

## Preflight

Before Task 1, install the one build-time tool the plan depends on and make sure Xcode is the active developer directory:

```bash
brew install xcodegen
xcodegen --version                                              # expect 2.x
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer # point at Xcode, not CommandLineTools
sudo xcodebuild -license accept                                 # one-time Xcode license acceptance
xcodebuild -runFirstLaunch                                      # one-time Xcode first-launch install
```

If Homebrew is unavailable, download the `xcodegen` release from https://github.com/yonaskolb/XcodeGen/releases and put it on `PATH`.

---

## File Structure

All paths are relative to `/Users/craigmdennis/Sites/macos-camera-viewer`.

```
.
├── .gitignore                                   # Xcode + macOS noise + Frameworks/
├── README.md                                    # How to run, config URL, smoke tests
├── project.yml                                  # xcodegen input — single source of truth
├── scripts/
│   └── bootstrap.sh                             # downloads VLCKit.xcframework (idempotent)
├── Frameworks/                                  # gitignored; populated by bootstrap.sh
│   └── VLCKit.xcframework/
├── CameraViewer.xcodeproj/                      # generated; gitignored
├── CameraViewer/
│   ├── Info.plist                               # hand-written (LSUIElement, ATS, usage string)
│   ├── CameraViewer.entitlements                # hardened runtime + network client
│   ├── CameraViewerApp.swift                    # @main SwiftUI App + NSApplicationDelegateAdaptor
│   ├── AppDelegate.swift                        # lifecycle wiring
│   ├── Window/
│   │   ├── PiPWindow.swift                      # NSWindow subclass
│   │   ├── PiPWindowController.swift            # owns window, player, chrome, persistence
│   │   └── CornerSnap.swift                     # pure: frame + screen → snapped frame
│   ├── Player/
│   │   ├── CameraPlayer.swift                   # VLCMediaPlayer wrapper, Combine state
│   │   └── ReconnectPolicy.swift                # pure: backoff sequence
│   ├── Chrome/
│   │   ├── ChromeOverlay.swift                  # SwiftUI close + mute buttons
│   │   └── HoverTrackingView.swift              # NSView + NSTrackingArea, publishes hover
│   ├── Config/
│   │   ├── AppConfig.swift                      # Codable { rtspsURL }, load/stub
│   │   └── Persistence.swift                    # UserDefaults wrapper (frame, muted)
│   └── MenuBar/
│       └── StatusItemController.swift           # NSStatusItem + menu
└── CameraViewerTests/
    ├── CornerSnapTests.swift
    ├── ReconnectPolicyTests.swift
    ├── AppConfigTests.swift
    └── PersistenceTests.swift
```

Pure, AppKit-free modules (unit-tested): `CornerSnap`, `ReconnectPolicy`, `AppConfig`, `Persistence`.
Integration-tested (manual smoke checklist): everything else.

Commit after every task. Commit messages use conventional prefixes (`feat:`, `test:`, `chore:`, `docs:`).

---

## Task 1: Project scaffold

**Files:**
- Create: `.gitignore`
- Create: `project.yml`
- Create: `CameraViewer/Info.plist`
- Create: `CameraViewer/CameraViewer.entitlements`
- Create: `CameraViewer/CameraViewerApp.swift` (placeholder that builds)
- Create: `CameraViewer/AppDelegate.swift` (placeholder)
- Create: `CameraViewerTests/SmokeTest.swift` (placeholder that builds and passes)
- Create: `README.md`

- [ ] **Step 1: Create `.gitignore`**

```gitignore
# macOS
.DS_Store

# Xcode
build/
DerivedData/
*.xcworkspace/xcuserdata/
*.xcodeproj/xcuserdata/
*.xcodeproj/project.xcworkspace/xcuserdata/
CameraViewer.xcodeproj/

# Swift Package Manager
.swiftpm/
.build/
Package.resolved

# Downloaded frameworks (fetched by scripts/bootstrap.sh)
Frameworks/
```

- [ ] **Step 2: Create `project.yml` (xcodegen input)**

```yaml
name: CameraViewer
options:
  deploymentTarget:
    macOS: "13.0"
  createIntermediateGroups: true
  generateEmptyDirectories: true
targets:
  CameraViewer:
    type: application
    platform: macOS
    sources:
      - path: CameraViewer
        excludes:
          - "Info.plist"
          - "CameraViewer.entitlements"
    dependencies:
      - framework: Frameworks/VLCKit.xcframework
        embed: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.craigmdennis.cameraviewer
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: "1"
        CODE_SIGN_STYLE: Automatic
        CODE_SIGN_IDENTITY: "-"
        ENABLE_HARDENED_RUNTIME: YES
        CODE_SIGN_ENTITLEMENTS: CameraViewer/CameraViewer.entitlements
        GENERATE_INFOPLIST_FILE: NO
        INFOPLIST_FILE: CameraViewer/Info.plist
        SWIFT_VERSION: "5.10"
        MACOSX_DEPLOYMENT_TARGET: "13.0"
  CameraViewerTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: CameraViewerTests
    dependencies:
      - target: CameraViewer
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.craigmdennis.cameraviewer.tests
        SWIFT_VERSION: "5.10"
        MACOSX_DEPLOYMENT_TARGET: "13.0"
        GENERATE_INFOPLIST_FILE: YES
```

> Note: VLCKit has no `Package.swift` at any of its release tags, so the SPM path doesn't work. We consume it as a prebuilt xcframework fetched by `scripts/bootstrap.sh` (see Step 2b below). Do **not** put an `info:` block on the `CameraViewer` target — combined with `INFOPLIST_FILE`, xcodegen will regenerate `Info.plist` on every run and wipe the hand-maintained keys.

- [ ] **Step 2b: Create `scripts/bootstrap.sh` and make it executable**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Downloads VLCKit.xcframework into Frameworks/. Idempotent.

VLCKIT_URL="https://artifacts.videolan.org/VLCKit/VLCKit/VLCKit-3.7.3-319ed2c0-79128878.tar.xz"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRAMEWORKS_DIR="$ROOT/Frameworks"
XCFRAMEWORK="$FRAMEWORKS_DIR/VLCKit.xcframework"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ -d "$XCFRAMEWORK" ]]; then
    echo "VLCKit.xcframework already present. Skipping."
    exit 0
fi

echo "Downloading VLCKit.xcframework..."
mkdir -p "$FRAMEWORKS_DIR"
curl -fL --progress-bar -o "$TMP_DIR/vlckit.tar.xz" "$VLCKIT_URL"

echo "Extracting..."
tar -xJf "$TMP_DIR/vlckit.tar.xz" -C "$TMP_DIR"
cp -R "$TMP_DIR/VLCKit - binary package/VLCKit.xcframework" "$FRAMEWORKS_DIR/"

echo "VLCKit.xcframework installed at $XCFRAMEWORK"
```

Then `chmod +x scripts/bootstrap.sh && ./scripts/bootstrap.sh` to fetch the framework (~38 MB download, ~150 MB extracted).

- [ ] **Step 3: Create `CameraViewer/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>$(DEVELOPMENT_LANGUAGE)</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
    <key>CFBundleShortVersionString</key>
    <string>$(MARKETING_VERSION)</string>
    <key>CFBundleVersion</key>
    <string>$(CURRENT_PROJECT_VERSION)</string>
    <key>LSMinimumSystemVersion</key>
    <string>$(MACOSX_DEPLOYMENT_TARGET)</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCameraUsageDescription</key>
    <string>Displays your Unifi Protect camera feed.</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
```

- [ ] **Step 4: Create `CameraViewer/CameraViewer.entitlements`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 5: Create placeholder Swift files so the project builds**

`CameraViewer/CameraViewerApp.swift`:

```swift
import SwiftUI

@main
struct CameraViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }  // No Settings window; SwiftUI requires a Scene.
    }
}
```

`CameraViewer/AppDelegate.swift`:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Wired up in later tasks.
    }
}
```

`CameraViewerTests/SmokeTest.swift`:

```swift
import XCTest

final class SmokeTest: XCTestCase {
    func testBuilds() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 6: Create `README.md`**

```markdown
# Camera Viewer

A single-window macOS app that displays a local Unifi Protect RTSPS camera feed as a Picture-in-Picture–style floating window.

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15+
- `xcodegen` (`brew install xcodegen`)
- A Unifi Protect camera with RTSPS enabled, reachable on the local network.

## Getting started

```sh
xcodegen generate
open CameraViewer.xcodeproj
# ⌘R in Xcode to build and run
```

On first launch the app writes a stub config to `~/Library/Application Support/CameraViewer/config.json` and opens it in TextEdit. Replace `rtspsURL` with your camera's RTSPS URL (find it in the Protect web UI → Settings → Advanced → RTSP, e.g. `rtsps://10.0.0.1:7441/YOUR_CAMERA_ID?enableSrtp`), save, and relaunch.

## Manual smoke tests

(See Task 13 in `docs/superpowers/plans/2026-04-17-macos-camera-viewer.md`.)

## Licensing

This app dynamically links VLCKit, which is LGPL-2.1-or-later. See https://code.videolan.org/videolan/VLCKit for details. Personal use is unrestricted.
```

- [ ] **Step 7: Bootstrap VLCKit, generate the Xcode project, and verify it builds**

Run: `./scripts/bootstrap.sh`
Expected: `VLCKit.xcframework installed at <path>` on first run, or `already present` on subsequent runs.

Run: `xcodegen generate`
Expected: `Created project at CameraViewer.xcodeproj`

Run: `xcodebuild -project CameraViewer.xcodeproj -scheme CameraViewer -configuration Debug build | tail -5`
Expected: `** BUILD SUCCEEDED **`

Run: `xcodebuild -project CameraViewer.xcodeproj -scheme CameraViewer -destination 'platform=macOS' test | tail -5`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add .gitignore project.yml README.md scripts/ CameraViewer/ CameraViewerTests/
git commit -m "chore: project scaffold with xcodegen, VLCKit xcframework, smoke test"
```

---

## Task 2: `AppConfig` — TDD

Pure Codable model plus a loader/stub-writer that touches `~/Library/Application Support/CameraViewer/config.json`.

**Files:**
- Create: `CameraViewer/Config/AppConfig.swift`
- Create: `CameraViewerTests/AppConfigTests.swift`

- [ ] **Step 1: Write the failing tests**

`CameraViewerTests/AppConfigTests.swift`:

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
        let original = AppConfig(rtspsURL: URL(string: "rtsps://10.0.0.1:7441/abc?enableSrtp")!)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testDecodeIgnoresUnknownKeys() throws {
        let json = #"""
        { "_comment": "hello", "rtspsURL": "rtsps://10.0.0.1:7441/abc?enableSrtp" }
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfig.self, from: json)
        XCTAssertEqual(decoded.rtspsURL.absoluteString, "rtsps://10.0.0.1:7441/abc?enableSrtp")
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

    func testWriteStubCreatesDirectoryAndValidJSON() throws {
        let url = tmpDir
            .appendingPathComponent("sub", isDirectory: true)
            .appendingPathComponent("config.json")
        try AppConfigLoader.writeStub(to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let reloaded = try AppConfigLoader.load(from: url)
        XCTAssertEqual(reloaded.rtspsURL.scheme, "rtsps")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail to compile**

Run: `xcodebuild -project CameraViewer.xcodeproj -scheme CameraViewer -destination 'platform=macOS' test 2>&1 | grep -E "error:" | head`
Expected: errors about `AppConfig`, `AppConfigLoader`, and `AppConfigError` not being in scope.

- [ ] **Step 3: Write `CameraViewer/Config/AppConfig.swift`**

```swift
import Foundation

struct AppConfig: Codable, Equatable {
    var rtspsURL: URL
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
            return try JSONDecoder().decode(AppConfig.self, from: data)
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
          "_comment": "Replace rtspsURL with your camera's RTSPS URL (Protect web UI → Settings → Advanced → RTSP).",
          "rtspsURL": "rtsps://10.0.0.1:7441/YOUR_CAMERA_ID?enableSrtp"
        }

        """
        try Data(stub.utf8).write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project CameraViewer.xcodeproj -scheme CameraViewer -destination 'platform=macOS' test 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add CameraViewer/Config/AppConfig.swift CameraViewerTests/AppConfigTests.swift project.yml
git commit -m "feat: AppConfig codec and loader with stub writer"
```

---

## Task 3: `Persistence` — TDD

Thin wrapper over `UserDefaults` for window frame and mute state. Injectable `UserDefaults` so tests use a throwaway suite.

**Files:**
- Create: `CameraViewer/Config/Persistence.swift`
- Create: `CameraViewerTests/PersistenceTests.swift`

- [ ] **Step 1: Write the failing tests**

`CameraViewerTests/PersistenceTests.swift`:

```swift
import XCTest
import AppKit
@testable import CameraViewer

final class PersistenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PersistenceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testLoadFrameReturnsNilWhenUnset() {
        let p = Persistence(defaults: defaults)
        XCTAssertNil(p.loadFrame())
    }

    func testRoundTripFrame() {
        let p = Persistence(defaults: defaults)
        let rect = NSRect(x: 100, y: 200, width: 640, height: 360)
        p.saveFrame(rect)
        XCTAssertEqual(p.loadFrame(), rect)
    }

    func testLoadMutedDefaultsToTrueWhenUnset() {
        let p = Persistence(defaults: defaults)
        XCTAssertTrue(p.loadMuted(), "first launch should default to muted")
    }

    func testRoundTripMuted() {
        let p = Persistence(defaults: defaults)
        p.saveMuted(false)
        XCTAssertFalse(p.loadMuted())
        p.saveMuted(true)
        XCTAssertTrue(p.loadMuted())
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail to compile**

Run: `xcodebuild -project CameraViewer.xcodeproj -scheme CameraViewer -destination 'platform=macOS' test 2>&1 | grep -E "error:" | head`
Expected: errors about `Persistence` not being in scope.

- [ ] **Step 3: Write `CameraViewer/Config/Persistence.swift`**

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
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project CameraViewer.xcodeproj -scheme CameraViewer -destination 'platform=macOS' test 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add CameraViewer/Config/Persistence.swift CameraViewerTests/PersistenceTests.swift
git commit -m "feat: Persistence wrapper for window frame and mute state"
```

---

## Task 4: `CornerSnap` — TDD

Pure function. Given a window frame and a screen's visible frame, return a snapped frame if the window's center is within 80 px of any corner, otherwise return the input unchanged.

**Files:**
- Create: `CameraViewer/Window/CornerSnap.swift`
- Create: `CameraViewerTests/CornerSnapTests.swift`

- [ ] **Step 1: Write the failing tests**

`CameraViewerTests/CornerSnapTests.swift`:

```swift
import XCTest
@testable import CameraViewer

final class CornerSnapTests: XCTestCase {
    // Use a screen visibleFrame of (0,0, 1920,1080) throughout.
    private let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
    private let windowSize = NSSize(width: 480, height: 270)

    private func window(at origin: NSPoint) -> NSRect {
        NSRect(origin: origin, size: windowSize)
    }

    func testSnapsToBottomLeftWhenCenterNearCorner() {
        // Window center a few px from bottom-left corner
        let originNearBL = NSPoint(x: -windowSize.width / 2 + 10, y: -windowSize.height / 2 + 10)
        let snapped = CornerSnap.snap(windowFrame: window(at: originNearBL), screenVisibleFrame: screen)
        XCTAssertEqual(snapped.origin, NSPoint(x: 8, y: 8))
        XCTAssertEqual(snapped.size, windowSize)
    }

    func testSnapsToBottomRight() {
        let origin = NSPoint(x: screen.maxX - windowSize.width / 2 - 10,
                             y: -windowSize.height / 2 + 10)
        let snapped = CornerSnap.snap(windowFrame: window(at: origin), screenVisibleFrame: screen)
        XCTAssertEqual(snapped.origin, NSPoint(x: screen.maxX - windowSize.width - 8, y: 8))
    }

    func testSnapsToTopLeft() {
        let origin = NSPoint(x: -windowSize.width / 2 + 10,
                             y: screen.maxY - windowSize.height / 2 - 10)
        let snapped = CornerSnap.snap(windowFrame: window(at: origin), screenVisibleFrame: screen)
        XCTAssertEqual(snapped.origin, NSPoint(x: 8, y: screen.maxY - windowSize.height - 8))
    }

    func testSnapsToTopRight() {
        let origin = NSPoint(x: screen.maxX - windowSize.width / 2 - 10,
                             y: screen.maxY - windowSize.height / 2 - 10)
        let snapped = CornerSnap.snap(windowFrame: window(at: origin), screenVisibleFrame: screen)
        XCTAssertEqual(snapped.origin,
                       NSPoint(x: screen.maxX - windowSize.width - 8,
                               y: screen.maxY - windowSize.height - 8))
    }

    func testDoesNotSnapWhenCenteredOnScreen() {
        let origin = NSPoint(x: screen.midX - windowSize.width / 2,
                             y: screen.midY - windowSize.height / 2)
        let frame = window(at: origin)
        XCTAssertEqual(CornerSnap.snap(windowFrame: frame, screenVisibleFrame: screen), frame)
    }

    func testDoesNotSnapJustBeyondThreshold() {
        // Center is exactly 81 px from bottom-left corner — outside default threshold of 80.
        let dx: CGFloat = 81 / sqrt(2)
        let origin = NSPoint(x: dx - windowSize.width / 2, y: dx - windowSize.height / 2)
        let frame = window(at: origin)
        XCTAssertEqual(CornerSnap.snap(windowFrame: frame, screenVisibleFrame: screen), frame)
    }

    func testSnapsExactlyAtThreshold() {
        let dx: CGFloat = 80 / sqrt(2)
        let origin = NSPoint(x: dx - windowSize.width / 2, y: dx - windowSize.height / 2)
        let snapped = CornerSnap.snap(windowFrame: window(at: origin), screenVisibleFrame: screen)
        XCTAssertEqual(snapped.origin, NSPoint(x: 8, y: 8))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail to compile**

Run: `xcodebuild -project CameraViewer.xcodeproj -scheme CameraViewer -destination 'platform=macOS' test 2>&1 | grep -E "error:" | head`
Expected: errors about `CornerSnap` not being in scope.

- [ ] **Step 3: Write `CameraViewer/Window/CornerSnap.swift`**

```swift
import AppKit

enum CornerSnap {
    static let defaultThreshold: CGFloat = 80
    static let defaultInset: CGFloat = 8

    enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    static func snap(
        windowFrame: NSRect,
        screenVisibleFrame screen: NSRect,
        threshold: CGFloat = defaultThreshold,
        inset: CGFloat = defaultInset
    ) -> NSRect {
        let center = NSPoint(x: windowFrame.midX, y: windowFrame.midY)
        let corners: [(Corner, NSPoint)] = [
            (.topLeft,     NSPoint(x: screen.minX, y: screen.maxY)),
            (.topRight,    NSPoint(x: screen.maxX, y: screen.maxY)),
            (.bottomLeft,  NSPoint(x: screen.minX, y: screen.minY)),
            (.bottomRight, NSPoint(x: screen.maxX, y: screen.minY))
        ]

        let nearest = corners.min { distance($0.1, center) < distance($1.1, center) }!
        guard distance(nearest.1, center) <= threshold else {
            return windowFrame
        }
        return frame(for: nearest.0, size: windowFrame.size, in: screen, inset: inset)
    }

    private static func distance(_ a: NSPoint, _ b: NSPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    private static func frame(for corner: Corner, size: NSSize, in screen: NSRect, inset: CGFloat) -> NSRect {
        switch corner {
        case .topLeft:
            return NSRect(x: screen.minX + inset,
                          y: screen.maxY - size.height - inset,
                          width: size.width, height: size.height)
        case .topRight:
            return NSRect(x: screen.maxX - size.width - inset,
                          y: screen.maxY - size.height - inset,
                          width: size.width, height: size.height)
        case .bottomLeft:
            return NSRect(x: screen.minX + inset,
                          y: screen.minY + inset,
                          width: size.width, height: size.height)
        case .bottomRight:
            return NSRect(x: screen.maxX - size.width - inset,
                          y: screen.minY + inset,
                          width: size.width, height: size.height)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project CameraViewer.xcodeproj -scheme CameraViewer -destination 'platform=macOS' test 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add CameraViewer/Window/CornerSnap.swift CameraViewerTests/CornerSnapTests.swift
git commit -m "feat: CornerSnap pure geometry with threshold + inset"
```

---

## Task 5: `ReconnectPolicy` — TDD

Pure struct that produces the next retry delay and resets on success.

**Files:**
- Create: `CameraViewer/Player/ReconnectPolicy.swift`
- Create: `CameraViewerTests/ReconnectPolicyTests.swift`

- [ ] **Step 1: Write the failing tests**

`CameraViewerTests/ReconnectPolicyTests.swift`:

```swift
import XCTest
@testable import CameraViewer

final class ReconnectPolicyTests: XCTestCase {
    func testSequenceStartsAtOneAndCapsAtTen() {
        var policy = ReconnectPolicy()
        let delays = (0..<7).map { _ in policy.recordFailure() }
        XCTAssertEqual(delays, [1, 2, 4, 8, 10, 10, 10])
    }

    func testResetReturnsToStart() {
        var policy = ReconnectPolicy()
        _ = policy.recordFailure()
        _ = policy.recordFailure()
        _ = policy.recordFailure()
        policy.reset()
        XCTAssertEqual(policy.recordFailure(), 1)
    }

    func testConsecutiveFailuresCounter() {
        var policy = ReconnectPolicy()
        XCTAssertEqual(policy.consecutiveFailures, 0)
        _ = policy.recordFailure()
        XCTAssertEqual(policy.consecutiveFailures, 1)
        _ = policy.recordFailure()
        XCTAssertEqual(policy.consecutiveFailures, 2)
        policy.reset()
        XCTAssertEqual(policy.consecutiveFailures, 0)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail to compile**

Run: `xcodebuild -project CameraViewer.xcodeproj -scheme CameraViewer -destination 'platform=macOS' test 2>&1 | grep -E "error:" | head`
Expected: errors about `ReconnectPolicy` not being in scope.

- [ ] **Step 3: Write `CameraViewer/Player/ReconnectPolicy.swift`**

```swift
import Foundation

struct ReconnectPolicy {
    static let schedule: [TimeInterval] = [1, 2, 4, 8, 10]

    private(set) var consecutiveFailures: Int = 0

    mutating func recordFailure() -> TimeInterval {
        let index = min(consecutiveFailures, Self.schedule.count - 1)
        consecutiveFailures += 1
        return Self.schedule[index]
    }

    mutating func reset() {
        consecutiveFailures = 0
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project CameraViewer.xcodeproj -scheme CameraViewer -destination 'platform=macOS' test 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add CameraViewer/Player/ReconnectPolicy.swift CameraViewerTests/ReconnectPolicyTests.swift
git commit -m "feat: ReconnectPolicy exponential backoff capped at 10s"
```

---

## Task 6: `CameraPlayer` — VLCKit wrapper

Not TDD — wraps `VLCMediaPlayer`. Exposes a Combine-published state, a `play(url:)`, a `setMuted(_:)`, and attaches to an `NSView` for video output. Verified manually at the end.

**Files:**
- Create: `CameraViewer/Player/CameraPlayer.swift`

- [ ] **Step 1: Write the player**

```swift
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
```

- [ ] **Step 2: Build (no new tests — VLCKit integration is verified in Task 13)**

Run: `xcodebuild -project CameraViewer.xcodeproj -scheme CameraViewer -configuration Debug build | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add CameraViewer/Player/CameraPlayer.swift
git commit -m "feat: CameraPlayer VLCKit wrapper with published state and mute"
```

---

## Task 7: `HoverTrackingView`

AppKit view that installs a single `NSTrackingArea` covering its bounds and publishes hover changes via a Combine subject.

**Files:**
- Create: `CameraViewer/Chrome/HoverTrackingView.swift`

- [ ] **Step 1: Write the view**

```swift
import AppKit
import Combine

final class HoverTrackingView: NSView {
    let isHovered = CurrentValueSubject<Bool, Never>(false)

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered.send(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered.send(false)
    }

    override var isFlipped: Bool { true }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project CameraViewer.xcodeproj -scheme CameraViewer -configuration Debug build | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add CameraViewer/Chrome/HoverTrackingView.swift
git commit -m "feat: HoverTrackingView publishing hover state via Combine"
```

---

## Task 8: `ChromeOverlay` (SwiftUI)

SwiftUI view with close + mute buttons on a translucent HUD panel. Alpha is driven by a `@Binding<Bool>` fed from hover state with the 2 s delay applied upstream in `PiPWindowController`.

**Files:**
- Create: `CameraViewer/Chrome/ChromeOverlay.swift`

- [ ] **Step 1: Write the overlay**

```swift
import SwiftUI

struct ChromeOverlay: View {
    let isVisible: Bool
    let isMuted: Bool
    let onClose: () -> Void
    let onToggleMute: () -> Void

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")

                Button(action: onToggleMute) {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isMuted ? "Unmute" : "Mute")
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                    .clipShape(Capsule())
            )
            .padding(.top, 10)

            Spacer()
        }
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: isVisible ? 0.15 : 0.25), value: isVisible)
        .allowsHitTesting(isVisible)
    }
}

private struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project CameraViewer.xcodeproj -scheme CameraViewer -configuration Debug build | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add CameraViewer/Chrome/ChromeOverlay.swift
git commit -m "feat: ChromeOverlay SwiftUI HUD with close and mute"
```

---

## Task 9: `PiPWindow`

`NSWindow` subclass with the level, collection behavior, style mask, aspect-ratio lock, and an `acceptsFirstMouse` override so a single click on the window can both focus and act.

**Files:**
- Create: `CameraViewer/Window/PiPWindow.swift`

- [ ] **Step 1: Write the subclass**

```swift
import AppKit

final class PiPWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        hasShadow = true
        backgroundColor = .black
        isOpaque = true
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project CameraViewer.xcodeproj -scheme CameraViewer -configuration Debug build | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add CameraViewer/Window/PiPWindow.swift
git commit -m "feat: PiPWindow borderless resizable window at screenSaver level"
```

---

## Task 10: `PiPWindowController`

Owns the window and wires everything together: player, hover tracking, chrome overlay, persistence, corner-snap, reconnect loop, aspect-ratio lock on first frame.

**Files:**
- Create: `CameraViewer/Window/PiPWindowController.swift`
- Modify: `CameraViewer/Player/CameraPlayer.swift` (add `videoSize` getter)

- [ ] **Step 1: Add a `videoSize` getter to `CameraPlayer`**

In `CameraViewer/Player/CameraPlayer.swift`, inside the `CameraPlayer` class body near `isMuted`, add:

```swift
var videoSize: CGSize? {
    let size = player.videoSize
    return size == .zero ? nil : size
}
```

- [ ] **Step 2: Write `CameraViewer/Window/PiPWindowController.swift`**

```swift
import AppKit
import Combine
import SwiftUI

final class PiPWindowController: NSObject, NSWindowDelegate {
    let window: PiPWindow
    let player: CameraPlayer

    private let persistence: Persistence
    private let config: AppConfig
    private let hoverView: HoverTrackingView
    private var chromeHostingView: NSHostingView<ChromeOverlay>!
    private var reconnectPolicy = ReconnectPolicy()
    private var reconnectTimer: Timer?
    private var hoverFadeOutTimer: Timer?
    private var dragEndMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var chromeVisible = false

    // Exposed so StatusItemController can observe state.
    var playerStatePublisher: AnyPublisher<CameraPlayer.State, Never> {
        player.$state.eraseToAnyPublisher()
    }

    init(config: AppConfig, persistence: Persistence = Persistence()) {
        self.config = config
        self.persistence = persistence

        let initialFrame = Self.initialFrame(persisted: persistence.loadFrame())
        let window = PiPWindow(contentRect: initialFrame)
        self.window = window

        let hoverView = HoverTrackingView(frame: NSRect(origin: .zero, size: initialFrame.size))
        hoverView.autoresizingMask = [.width, .height]
        hoverView.wantsLayer = true
        hoverView.layer?.backgroundColor = NSColor.black.cgColor
        self.hoverView = hoverView

        self.player = CameraPlayer(drawable: hoverView, initiallyMuted: persistence.loadMuted())

        super.init()

        window.contentView = hoverView
        window.delegate = self

        installChrome()
        observeHover()
        observePlayerState()

        player.play(url: config.rtspsURL)
        window.setFrame(initialFrame, display: true)
        window.makeKeyAndOrderFront(nil)
    }

    deinit {
        reconnectTimer?.invalidate()
        hoverFadeOutTimer?.invalidate()
        if let monitor = dragEndMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Layout

    private static func initialFrame(persisted: NSRect?) -> NSRect {
        if let p = persisted, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(p) }) {
            return p
        }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 480, height: 270)
        let inset: CGFloat = 16
        return NSRect(x: screen.maxX - size.width - inset,
                      y: screen.minY + inset,
                      width: size.width, height: size.height)
    }

    private func installChrome() {
        let hosting = NSHostingView(rootView: currentOverlay())
        hosting.frame = hoverView.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        hoverView.addSubview(hosting)
        chromeHostingView = hosting
    }

    private func currentOverlay() -> ChromeOverlay {
        ChromeOverlay(
            isVisible: chromeVisible,
            isMuted: player.isMuted,
            onClose: { NSApp.terminate(nil) },
            onToggleMute: { [weak self] in self?.toggleMute() }
        )
    }

    private func refreshChrome() {
        chromeHostingView.rootView = currentOverlay()
    }

    // MARK: - Hover

    private func observeHover() {
        hoverView.isHovered
            .removeDuplicates()
            .sink { [weak self] hovered in self?.handleHover(hovered) }
            .store(in: &cancellables)
    }

    private func handleHover(_ hovered: Bool) {
        hoverFadeOutTimer?.invalidate()
        if hovered {
            chromeVisible = true
            refreshChrome()
        } else {
            hoverFadeOutTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                self?.chromeVisible = false
                self?.refreshChrome()
            }
        }
    }

    // MARK: - Mute

    private func toggleMute() {
        let next = !player.isMuted
        player.setMuted(next)
        persistence.saveMuted(next)
        refreshChrome()
    }

    // MARK: - Player state / reconnect

    private func observePlayerState() {
        player.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.handlePlayerState(state) }
            .store(in: &cancellables)
    }

    private func handlePlayerState(_ state: CameraPlayer.State) {
        switch state {
        case .playing:
            reconnectPolicy.reset()
            reconnectTimer?.invalidate()
            lockAspectRatioToVideoSize()
        case .error:
            scheduleReconnect()
        case .idle, .opening, .buffering:
            break
        }
    }

    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        let delay = reconnectPolicy.recordFailure()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.player.play(url: self.config.rtspsURL)
        }
    }

    private func lockAspectRatioToVideoSize() {
        guard let size = player.videoSize, size.width > 0, size.height > 0 else { return }
        window.contentAspectRatio = size
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        persistence.saveFrame(window.frame)
    }

    func windowDidMove(_ notification: Notification) {
        persistence.saveFrame(window.frame)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        persistence.saveFrame(window.frame)
    }

    // Corner snap on drag-end. AppKit doesn't expose "window drag ended" directly —
    // windowDidMove fires continuously during drag — so we listen for leftMouseUp in this window.
    func installDragEndSnap() {
        dragEndMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            let screen = self.window.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
            let snapped = CornerSnap.snap(windowFrame: self.window.frame, screenVisibleFrame: screen)
            if snapped != self.window.frame {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    self.window.animator().setFrame(snapped, display: true)
                }
                self.persistence.saveFrame(snapped)
            }
            return event
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project CameraViewer.xcodeproj -scheme CameraViewer -configuration Debug build | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add CameraViewer/Window/PiPWindowController.swift CameraViewer/Player/CameraPlayer.swift
git commit -m "feat: PiPWindowController wires window, player, chrome, persistence, reconnect"
```

---

## Task 11: `StatusItemController`

Menu-bar status item with Reveal Config, Reconnect, Quit. Icon reflects player state.

**Files:**
- Create: `CameraViewer/MenuBar/StatusItemController.swift`

- [ ] **Step 1: Write the controller**

```swift
import AppKit
import Combine

final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let onReconnect: () -> Void
    private var cancellables = Set<AnyCancellable>()
    private var lastErrorItem: NSMenuItem?
    private var lastErrorAt: Date?

    init(statePublisher: AnyPublisher<CameraPlayer.State, Never>, onReconnect: @escaping () -> Void) {
        self.onReconnect = onReconnect
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
        menu.addItem(NSMenuItem(title: "Reveal Config in Finder", action: #selector(revealConfig), keyEquivalent: ""))
        menu.items.last?.target = self
        menu.addItem(NSMenuItem(title: "Reconnect", action: #selector(reconnect), keyEquivalent: ""))
        menu.items.last?.target = self
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
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
        // Show "Last error: …" only after 30 s of continuous failure.
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
        let url = AppConfigLoader.defaultFileURL
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func reconnect() {
        onReconnect()
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project CameraViewer.xcodeproj -scheme CameraViewer -configuration Debug build | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add CameraViewer/MenuBar/StatusItemController.swift
git commit -m "feat: StatusItemController with reveal config, reconnect, quit"
```

---

## Task 12: `AppDelegate` + entry wiring

Load config (or write stub + alert on first launch), instantiate `PiPWindowController` and `StatusItemController`, and install the drag-end snap monitor.

**Files:**
- Modify: `CameraViewer/AppDelegate.swift`
- Modify: `CameraViewer/CameraViewerApp.swift` (no change expected, but verify)

- [ ] **Step 1: Replace `AppDelegate.swift`**

```swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: PiPWindowController?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let config: AppConfig
        do {
            config = try AppConfigLoader.load()
        } catch AppConfigError.fileNotFound(let path) {
            try? AppConfigLoader.writeStub(to: path)
            presentFirstLaunchAlert(path: path)
            NSWorkspace.shared.open(path)
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

        let controller = PiPWindowController(config: config)
        controller.installDragEndSnap()
        windowController = controller

        statusItemController = StatusItemController(
            statePublisher: controller.playerStatePublisher,
            onReconnect: { [weak controller] in
                guard let controller else { return }
                controller.player.stop()
                controller.player.play(url: config.rtspsURL)
            }
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
}
```

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild -project CameraViewer.xcodeproj -scheme CameraViewer -configuration Debug build | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run all unit tests one more time**

Run: `xcodebuild -project CameraViewer.xcodeproj -scheme CameraViewer -destination 'platform=macOS' test 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add CameraViewer/AppDelegate.swift
git commit -m "feat: AppDelegate wires config loading, window controller, status item"
```

---

## Task 13: Manual smoke test + README update

**Files:**
- Modify: `README.md` (append smoke-test checklist)

- [ ] **Step 1: Pre-requisites**

Prepare a valid config at `~/Library/Application Support/CameraViewer/config.json`:

```json
{ "rtspsURL": "rtsps://10.0.0.1:7441/ccA66GZzFoKTCyxD?enableSrtp" }
```

(Replace with the camera URL from the spec — the user's actual RTSPS URL.)

- [ ] **Step 2: Run the app from Xcode**

Open `CameraViewer.xcodeproj`, press ⌘R. Expect the app to launch with no Dock icon, a `video.fill` status-bar icon, and a video window bottom-right.

- [ ] **Step 3: Execute each check. For any failure, stop and fix before continuing.**

1. **Launch defaults** — window appears in the bottom-right of the main screen, 480×270 (or aspect-adjusted to the stream), playing silently.
2. **Hover chrome** — move the cursor into the window. Chrome fades in (~150 ms). Move the cursor out. Chrome stays for ~2 s, then fades out (~250 ms).
3. **Mute** — click the speaker icon, hear audio. Click again, audio mutes.
4. **Close** — click the X. App quits entirely (no residual status bar icon).
5. **Relaunch** — last position, size, and mute state restored. (Note: if you muted in step 3 and then quit unmuted, the last saved value is what you should see.)
6. **Corner snap** — drag the window so its centre is close to the top-left corner and release. It snaps with an 8 px inset. Repeat for each corner.
7. **No snap in the middle** — drag to the middle and release. It stays where you dropped it.
8. **Aspect lock** — drag a corner to resize. The window holds 16:9 (or the camera's reported aspect).
9. **No edge resize** — dragging the middle of an edge does *not* resize (you may still be able to drag-move from there, which is fine).
10. **Across Spaces** — swipe to another Space with a three-finger gesture. Window follows.
11. **Over fullscreen** — put Safari or another app into fullscreen. Camera window remains visible on top.
12. **Network drop** — disable Wi-Fi / unplug Ethernet. Within ~5 s, status-bar icon turns into `video.slash.fill`. Re-enable the network. Within the current backoff window, the stream resumes and the icon returns to `video.fill`. No user interaction required.
13. **After 30 s of continuous failure**, open the menu bar menu. A disabled "Last error: …" item appears at the top. It disappears once the stream recovers.
14. **Reveal Config** — open the status menu → "Reveal Config in Finder". Finder opens at the config file.
15. **Reconnect** — edit `config.json`, change the URL to an invalid one and save. Click the status menu → "Reconnect". App enters error/retry. Put the correct URL back, Reconnect again, stream resumes.

- [ ] **Step 4: Append the checklist to `README.md`**

Append the contents of Step 3 (items 1–15) to `README.md` under a `## Manual smoke tests` heading, replacing the placeholder pointer added in Task 1.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: manual smoke-test checklist in README"
```

---

## Self-Review

Done. Coverage against the spec:

- **Window behavior** — PiPWindow (Task 9), PiPWindowController (Task 10): level, collection behavior, borderless + resizable, aspect ratio, corner snap via `CornerSnap` (Task 4), drag-end monitor in Task 10/12.
- **Chrome** — HoverTrackingView (Task 7), ChromeOverlay (Task 8), fade-in/out driven by PiPWindowController (Task 10).
- **Menu bar** — StatusItemController (Task 11): Reveal Config, Reconnect, Quit, icon reflects state, "Last error" after 30 s.
- **Player + reconnect** — CameraPlayer (Task 6), ReconnectPolicy (Task 5), handling in PiPWindowController (Task 10).
- **Config + persistence** — AppConfig (Task 2), Persistence (Task 3), first-launch stub + alert in AppDelegate (Task 12).
- **Build** — project.yml, Info.plist, entitlements, hardened runtime, ad-hoc signing (Task 1).
- **Tests** — unit tests for the four pure modules (Tasks 2–5); manual smoke checklist (Task 13).
- **Out of scope (spec)** — launch-at-login: not in plan ✓. In-app settings UI: not in plan ✓. Multi-camera: not in plan ✓.

No placeholders, no "TBD", no "similar to earlier task". Type/method names consistent across tasks (`PiPWindow`, `PiPWindowController`, `CameraPlayer.State`, `ReconnectPolicy.recordFailure/reset`, `AppConfigLoader.load/writeStub`, `Persistence.loadFrame/saveFrame/loadMuted/saveMuted`, `CornerSnap.snap`).

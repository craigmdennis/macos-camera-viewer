# Feature Changelog

## Multi-camera selection (2026-04-20)

Replaced single-camera config with a named camera array. Users select the active camera from a menu-bar submenu; the selection persists across launches.

### Config format changed

Old (`rtspsURL` key no longer works):
```json
{ "rtspsURL": "rtsps://..." }
```

New:
```json
{
  "cameras": [
    { "name": "Front Door", "uri": "rtsps://10.0.0.1:7441/CAMERA_ID?enableSrtp" }
  ]
}
```

### Files changed

| File | Change |
|------|--------|
| `CameraViewer/Config/AppConfig.swift` | `AppConfig` now holds `cameras: [CameraConfig]`; `CameraConfig` has `name: String` and `uri: URL`; `load()` rejects empty arrays |
| `CameraViewer/Config/Persistence.swift` | Added `selectedCameraName` load/save (UserDefaults key `selectedCameraName`) |
| `CameraViewer/MenuBar/StatusItemController.swift` | Added `cameras`, `selectedCameraName`, `onSelectCamera` closures; Cameras submenu rebuilt on every `menuWillOpen` |
| `CameraViewer/AppDelegate.swift` | Resolves active camera on launch by persisted name (fallback to `cameras[0]`); wires `onSelectCamera` through proxy restart + `updateStreamURL` |
| `CameraViewerTests/AppConfigTests.swift` | Full rewrite for new model; covers empty-array and missing-cameras-key error paths |
| `CameraViewerTests/PersistenceTests.swift` | Added `selectedCameraName` round-trip tests |
| `config.example.json` | Updated to multi-camera format |
| `Makefile` | `APP_NAME` updated to `Camera Viewer` (with space) |
| `README.md` | Configuration section updated for new format |

### Key decisions

- Camera selection persists by **name**, not index — survives reordering
- `onReconnect` reloads config from disk so URI edits take effect without restarting
- Submenu rebuilt fresh on every open — no change observation needed
- `StreamProxy` (go2rtc subprocess) is restarted on every camera switch

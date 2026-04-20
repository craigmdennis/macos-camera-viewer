# Multi-Camera Selection — Design

**Date:** 2026-04-20
**Status:** Approved

## Summary

Add support for multiple cameras defined in `config.json`. The user selects the active camera from a "Cameras" submenu in the menu-bar menu. The last selected camera persists across launches.

## Goals

- Define cameras as an array of `{ name, uri }` objects in `config.json`.
- Select the active camera from a "Cameras" submenu (checkmark on active item).
- Persist the last selected camera by name across launches.
- Switching cameras restarts the stream proxy and reconnects immediately.

## Non-Goals

- Multiple simultaneous camera windows (one PiP window only).
- In-app camera management UI (config file is the source of truth).

## Config Shape

Path: `~/Library/Application Support/CameraViewer/config.json`

```json
{
  "cameras": [
    { "name": "Front Door", "uri": "rtsps://10.0.0.1:7441/CAMERA_ID_1?enableSrtp" },
    { "name": "Back Yard",  "uri": "rtsps://10.0.0.1:7441/CAMERA_ID_2?enableSrtp" }
  ]
}
```

Old single-URL configs (`{ "rtspsURL": "..." }`) decode as malformed — the existing error alert fires, with updated text pointing to the new format.

Zero cameras in the array is treated as malformed (same alert path).

The stub written on first launch shows a two-camera example.

## Data Model

```swift
struct CameraConfig: Codable, Equatable {
    var name: String
    var uri: URL
}

struct AppConfig: Codable, Equatable {
    var cameras: [CameraConfig]  // must be non-empty
}
```

`AppConfigLoader` validates `cameras.isEmpty` after decode and throws `.malformed` if true.

## Persistence

`Persistence` gains one new UserDefaults key:

| Key | Type | Notes |
|-----|------|-------|
| `selectedCameraName` | `String?` | Name of the last active camera |

On launch, the active camera is resolved as:
1. `cameras.first(where: { $0.name == persistence.selectedCameraName })`, or
2. `cameras[0]` as fallback (camera renamed/removed between launches).

The resolved camera name is immediately re-persisted so the fallback sticks.

## Menu Layout

```
  Hide Camera          ← existing (dynamic title)
─────────────
▶ Cameras              ← new submenu
    ✓ Front Door
      Back Yard
─────────────
  Reveal Config in Finder
  Reconnect
─────────────
  Quit
```

The submenu is rebuilt in `menuWillOpen(_:)` so it always reflects the current config without needing change observation. Each camera item gets a `NSMenuItem.state = .on` checkmark when its name matches the active camera.

## Camera Switching

When the user selects a camera:

1. `Persistence.saveSelectedCameraName(camera.name)`
2. `StreamProxy.start(upstream: camera.uri)` — stops old go2rtc process, starts new one.
3. `PiPWindowController.updateStreamURL(StreamProxy.localURL)` — resets reconnect policy, stops player, starts playing new stream.
4. Submenu checkmark updates on next `menuWillOpen`.

`StatusItemController` receives two new closures:
- `onSelectCamera: (CameraConfig) -> Void` — called when user picks a camera.
- `cameras: () -> [CameraConfig]` — returns current camera list for submenu population.
- `selectedCameraName: () -> String?` — returns current selection for checkmark rendering.

## Error Handling

| Scenario | Behaviour |
|----------|-----------|
| Old `rtspsURL` config | Malformed alert fires; text updated to mention new format |
| `cameras` array is empty | Malformed alert fires |
| Selected camera missing from config on launch | Silently falls back to `cameras[0]`; new name persisted |
| Switch during active reconnect loop | `updateStreamURL` calls `reconnectPolicy.reset()` + `player.stop()` — loop cancels cleanly |

## Files Changed

| File | Change |
|------|--------|
| `Config/AppConfig.swift` | Replace `rtspsURL: URL` with `cameras: [CameraConfig]`; add empty-array validation |
| `Config/Persistence.swift` | Add `selectedCameraName` load/save |
| `MenuBar/StatusItemController.swift` | Add Cameras submenu; add `onSelectCamera`, `cameras`, `selectedCameraName` closures |
| `AppDelegate.swift` | Resolve active camera on launch; wire `onSelectCamera` callback through proxy + window controller |

No new files required.

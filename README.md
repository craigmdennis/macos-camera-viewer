# Camera Viewer

A macOS menu-bar app that displays your Unifi Protect RTSPS camera feeds in a floating,
always-on-top Picture-in-Picture window. Fully native — no VLC, no ffmpeg, no subprocess:
RTSP/RTP is parsed and decoded in-process with VideoToolbox.

## Features

- **Floating PiP window** — borderless, always on top, draggable, resizable, snaps to
  the nearest screen corner when you let go.
- **Hover chrome** — controls fade in on hover and out when you move away, so the window
  stays unobtrusive the rest of the time.
- **Multiple cameras** — pick the active camera from the menu-bar **Cameras** submenu or
  the in-window picker; the selection is remembered across launches.
- **Multi-camera layouts** — watch 1, 2 (stacked), or 4 (grid) cameras at once. Switch
  layout from the menu bar's **Layout** submenu or the grid icon in the PiP overlay.
  Assign a camera to each tile independently; only one tile plays audio at a time.
  Click a tile's video to jump straight to single view on that camera, with a one-tap
  way back to the grid you came from. The window's aspect ratio locks itself to whatever
  keeps every visible camera filling its space, so there's no letterboxing.
- **Zoom & pan** — ⌘ + scroll to zoom in on a single camera (1×–8×), drag to pan while
  zoomed, double-click to reset.
- **Mute toggle** per view, remembered across launches.
- **Auto-reconnect** with backoff if a camera drops.

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15+
- `xcodegen` (`brew install xcodegen`)
- One or more Unifi Protect cameras with RTSPS enabled, reachable on the local network.

## Install

From the repo root:

```sh
xcodegen generate
make install
```

This generates the Xcode project, builds a Release binary, copies it to
`/Applications/Camera Viewer.app`, and clears the Gatekeeper quarantine flag. The first
time macOS may still ask you to confirm — click Open.

To remove:

```sh
make uninstall
```

To add Camera Viewer to Login Items so it launches at login: System Settings → General
→ Login Items → add Camera Viewer.

## Development

```sh
xcodegen generate
open CameraViewer.xcodeproj
# ⌘R in Xcode to build and run
```

No third-party frameworks to fetch — the whole media pipeline (RTSP, RTP, H.264/H.265
depacketizing, decode, display) is built on Apple frameworks only.

Other `make` targets:

| Target | Description |
|--------|-------------|
| `make build` | Release build only (no install) |
| `make install` | Build and copy to `/Applications` |
| `make uninstall` | Remove from `/Applications` |
| `make clean` | Clean Xcode build products |
| `make release` | Signed + notarized DMG (see `scripts/release.sh`) |
| `make release-unsigned` | Unsigned DMG, for local inspection of the release pipeline |

## Configuration

On first launch the app writes a stub config to
`~/Library/Application Support/CameraViewer/config.json` and opens it in TextEdit.
Replace the placeholder URIs with your cameras' RTSPS URLs, save, and relaunch.

Find your RTSPS URLs in the Protect web UI → camera Settings → Advanced → RTSP. The
config supports multiple cameras:

```json
{
  "cameras": [
    { "name": "Front Door", "uri": "rtsps://10.0.0.1:7441/YOUR_CAMERA_ID_1?enableSrtp" },
    { "name": "Back Yard",  "uri": "rtsps://10.0.0.1:7441/YOUR_CAMERA_ID_2?enableSrtp" }
  ]
}
```

Select the active camera from the **Cameras** submenu in the menu-bar icon, or assign
cameras per tile when using a 2 or 4-camera layout. Selections and per-tile assignments
are remembered across launches. Editing the config file and reopening Settings live-reloads
the camera list without restarting the app.

A `config.example.json` is included in this repo as a reference.

## Licensing

No third-party runtime dependencies — the media pipeline uses only Apple frameworks
(Network, AVFoundation, VideoToolbox). Personal use is unrestricted.

## Disclaimer

This codebase was generated with [Claude Code](https://claude.ai/code) (Anthropic). It
works for personal use but has not been formally audited or tested beyond the author's
own setup.

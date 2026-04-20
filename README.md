# Camera Viewer

A single-window macOS app that displays a local Unifi Protect RTSPS camera feed as a Picture-in-Picture–style floating window.

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15+
- `xcodegen` (`brew install xcodegen`)
- A Unifi Protect camera with RTSPS enabled, reachable on the local network.

## Install

```sh
make install
```

This builds a Release binary, copies it to `/Applications/CameraViewer.app`, and clears the Gatekeeper quarantine flag. The first time macOS may still ask you to confirm — click Open.

To remove:

```sh
make uninstall
```

To add Camera Viewer to Login Items so it launches at login: System Settings → General → Login Items → add CameraViewer.

## Development

```sh
./scripts/bootstrap.sh    # downloads VLCKit.xcframework into Frameworks/
xcodegen generate
open CameraViewer.xcodeproj
# ⌘R in Xcode to build and run
```

`scripts/bootstrap.sh` is idempotent; run it after a fresh clone and whenever `Frameworks/` is empty.

Other `make` targets:

| Target | Description |
|--------|-------------|
| `make build` | Release build only (no install) |
| `make install` | Build and copy to `/Applications` |
| `make uninstall` | Remove from `/Applications` |
| `make clean` | Clean Xcode build products |
| `make bootstrap` | Re-download VLCKit xcframework |

## Configuration

On first launch the app writes a stub config to `~/Library/Application Support/CameraViewer/config.json` and opens it in TextEdit. Replace the placeholder URIs with your cameras' RTSPS URLs, save, and relaunch.

Find your RTSPS URLs in the Protect web UI → camera Settings → Advanced → RTSP. The config supports multiple cameras:

```json
{
  "cameras": [
    { "name": "Front Door", "uri": "rtsps://10.0.0.1:7441/YOUR_CAMERA_ID_1?enableSrtp" },
    { "name": "Back Yard",  "uri": "rtsps://10.0.0.1:7441/YOUR_CAMERA_ID_2?enableSrtp" }
  ]
}
```

Select the active camera from the **Cameras** submenu in the menu-bar icon. The last selected camera is remembered across launches.

A `config.example.json` is included in this repo as a reference.


## Licensing

This app dynamically links VLCKit, which is LGPL-2.1-or-later. See https://code.videolan.org/videolan/VLCKit for details. Personal use is unrestricted.

## Disclaimer

This codebase was generated with [Claude Code](https://claude.ai/code) (Anthropic). It works for personal use but has not been formally audited or tested beyond the author's own setup.

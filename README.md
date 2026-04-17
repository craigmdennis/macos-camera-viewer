# Camera Viewer

A single-window macOS app that displays a local Unifi Protect RTSPS camera feed as a Picture-in-Picture–style floating window.

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15+
- `xcodegen` (`brew install xcodegen`)
- A Unifi Protect camera with RTSPS enabled, reachable on the local network.

## Getting started

```sh
./scripts/bootstrap.sh    # downloads VLCKit.xcframework into Frameworks/
xcodegen generate
open CameraViewer.xcodeproj
# ⌘R in Xcode to build and run
```

`scripts/bootstrap.sh` is idempotent; run it after a fresh clone and whenever `Frameworks/` is empty.

On first launch the app writes a stub config to `~/Library/Application Support/CameraViewer/config.json` and opens it in TextEdit. Replace `rtspsURL` with your camera's RTSPS URL (find it in the Protect web UI → Settings → Advanced → RTSP, e.g. `rtsps://10.0.0.1:7441/YOUR_CAMERA_ID?enableSrtp`), save, and relaunch.

## Manual smoke tests

(See Task 13 in `docs/superpowers/plans/2026-04-17-macos-camera-viewer.md`.)

## Licensing

This app dynamically links VLCKit, which is LGPL-2.1-or-later. See https://code.videolan.org/videolan/VLCKit for details. Personal use is unrestricted.

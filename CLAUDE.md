# Camera Viewer — Claude Instructions

## Before building any new feature

Read `docs/CHANGELOG.md` first. It summarises every feature added since the initial build: what changed, which files were touched, and key decisions made. This prevents re-litigating settled design choices and keeps new work consistent with existing patterns.

## Project overview

A macOS menu-bar app (no Dock icon) that displays RTSP camera streams in a floating PiP window. Single `NSWindow`, always on top, corner-snapping, hover chrome. Full design spec at `docs/superpowers/specs/2026-04-17-macos-camera-viewer-design.md`.

## Stack

- Swift + AppKit (window/menu) + SwiftUI (chrome overlay only)
- VLCKit 3.x for RTSP playback
- go2rtc subprocess (`bin/go2rtc`) to bridge RTSPS → plain RTSP
- No other third-party dependencies

## Conventions

- Files stay under ~150 lines
- Pure/logic code is unit-tested; AppKit/UI code is not
- Closures injected at init (not delegates) for testability
- `Persistence` = thin UserDefaults wrapper; `AppConfig` = disk-backed JSON
- No comments except where the WHY is non-obvious

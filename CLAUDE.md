# Camera Viewer — Claude Instructions

## Before building any new feature

Read `docs/CHANGELOG.md` first. It summarises every feature added since the initial build: what changed, which files were touched, and key decisions made. This prevents re-litigating settled design choices and keeps new work consistent with existing patterns.

## Project overview

A macOS menu-bar app (no Dock icon) that displays RTSP camera streams in a floating PiP window. Single `NSWindow`, always on top, corner-snapping, hover chrome, single/2-up/4-up layouts. Full design spec at `docs/superpowers/specs/2026-04-17-macos-camera-viewer-design.md`; native player rewrite at `docs/superpowers/specs/2026-05-29-native-rtsp-player-design.md`.

## Stack

- Swift + AppKit (window/menu) + SwiftUI (chrome overlay only)
- Fully native RTSP/RTP client (`CameraViewer/Player/RTSP`, `.../RTP`) + VideoToolbox decode via `AVSampleBufferDisplayLayer` — no VLCKit, no ffmpeg, no subprocess
- No third-party dependencies

## Conventions

- Files stay under ~150 lines
- Pure/logic code is unit-tested; AppKit/UI code is not
- Closures injected at init (not delegates) for testability
- `Persistence` = thin UserDefaults wrapper; `AppConfig` = disk-backed JSON
- No comments except where the WHY is non-obvious

## Blog content capture

This project is tracked for a portfolio blog post. Throughout sessions, maintain `blog/notes.md`.

Log:
- Key decisions and the reasoning behind them (especially where you rejected the obvious approach)
- Problems that came up in real testing and how they were fixed
- Moments where the plan changed mid-build and why
- Anything surprising or counterintuitive

One to three sentences per entry. Raw observations only — the `blog-post` skill turns them into prose.

Blog posts, images, and drafts go in `blog/`. This folder is gitignored — nothing in it is committed to the repo.

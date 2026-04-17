#!/usr/bin/env bash
set -euo pipefail

# Downloads VLCKit.xcframework into Frameworks/. Idempotent.
# The xcframework is gitignored so each clone runs this once.

VLCKIT_URL="https://artifacts.videolan.org/VLCKit/VLCKit/VLCKit-3.7.3-319ed2c0-79128878.tar.xz"
VLCKIT_SHA256="" # Intentionally empty; artifact is served over HTTPS from VideoLAN's infra.

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

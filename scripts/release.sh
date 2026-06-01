#!/usr/bin/env bash
set -euo pipefail

# Build → Developer ID sign → notarize → staple → DMG.
#
# Account-gated inputs (set these once you've enrolled in the Apple Developer Program):
#   DEVELOPER_ID   "Developer ID Application: Your Name (TEAMID)" — `security find-identity -v -p codesigning`
#   TEAM_ID        Your 10-char Apple Team ID
#   NOTARY_PROFILE Name of a stored notarytool credential profile (see below)
#
# Store the notary credential once (interactive), then this script is non-interactive:
#   xcrun notarytool store-credentials "CameraViewerNotary" \
#     --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw"
#   export NOTARY_PROFILE=CameraViewerNotary
#
# Until those exist the script stops early with a clear message — everything up to signing
# (build + DMG staging) still works for local inspection via: SKIP_SIGNING=1 ./scripts/release.sh

SCHEME="CameraViewer"
APP_NAME="Camera Viewer"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build-release"
DIST="$ROOT/dist"
APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
ENTITLEMENTS="$ROOT/CameraViewer/CameraViewer.entitlements"

echo "==> Generating project + building Release"
"$(command -v xcodegen)" generate >/dev/null
rm -rf "$DERIVED"
xcodebuild -scheme "$SCHEME" -configuration Release -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO build >/dev/null
echo "    built: $APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$DIST/$APP_NAME $VERSION.dmg"
# Version-less, space-less copy so the GitHub "latest" direct link stays stable across releases:
#   https://github.com/craigmdennis/macos-camera-viewer/releases/latest/download/CameraViewer.dmg
STABLE_DMG="$DIST/CameraViewer.dmg"
mkdir -p "$DIST"

if [[ "${SKIP_SIGNING:-0}" == "1" ]]; then
  echo "==> SKIP_SIGNING=1 — skipping sign/notarize, staging unsigned DMG for inspection only"
else
  : "${DEVELOPER_ID:?Set DEVELOPER_ID to your 'Developer ID Application: ...' identity (account-gated)}"
  : "${TEAM_ID:?Set TEAM_ID to your Apple Team ID (account-gated)}"
  : "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a stored notarytool credential profile (account-gated)}"

  echo "==> Signing with Developer ID (hardened runtime)"
  # Sign nested code first (none expected now that VLCKit/go2rtc are gone), then the app.
  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$DEVELOPER_ID" "$APP"
  codesign --verify --strict --verbose=2 "$APP"

  echo "==> Notarizing (submitting zip, waiting)"
  NOTARIZE_ZIP="$DIST/notarize.zip"
  ditto -c -k --keepParent "$APP" "$NOTARIZE_ZIP"
  xcrun notarytool submit "$NOTARIZE_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  rm -f "$NOTARIZE_ZIP"

  echo "==> Stapling"
  xcrun stapler staple "$APP"
fi

echo "==> Building DMG"
rm -f "$DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
cp "$DMG" "$STABLE_DMG"

if [[ "${SKIP_SIGNING:-0}" != "1" ]]; then
  for d in "$DMG" "$STABLE_DMG"; do
    codesign --force --sign "$DEVELOPER_ID" "$d"
    xcrun stapler staple "$d"        # staple each DMG so first-open works offline
  done
fi

echo "==> Done: $DMG"
echo "         $STABLE_DMG"
echo "    Upload to GitHub Releases:  gh release create v$VERSION \"$DMG\" \"$STABLE_DMG\" --title \"v$VERSION\" --generate-notes"

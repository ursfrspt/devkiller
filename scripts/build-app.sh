#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${DEVKILLER_APP_NAME:-DevKiller}"
PRODUCT_NAME="${DEVKILLER_PRODUCT_NAME:-devkillerbar}"
EXECUTABLE_NAME="${DEVKILLER_EXECUTABLE_NAME:-DevKiller}"
BUNDLE_ID="${DEVKILLER_BUNDLE_ID:-com.igyeongjun.DevKiller}"
MARKETING_VERSION="${DEVKILLER_VERSION:-0.1.0}"
BUILD_NUMBER="${DEVKILLER_BUILD_NUMBER:-1}"
CONFIGURATION="${DEVKILLER_CONFIGURATION:-release}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST="$CONTENTS_DIR/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Packaging/DevKiller.entitlements"

if [[ "$CONFIGURATION" != "release" && "$CONFIGURATION" != "debug" ]]; then
  echo "DEVKILLER_CONFIGURATION must be release or debug" >&2
  exit 1
fi

swift build -c "$CONFIGURATION" --product "$PRODUCT_NAME" >&2

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/.build/$CONFIGURATION/$PRODUCT_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
cp "$ROOT_DIR/Packaging/Info.plist" "$INFO_PLIST"
chmod 755 "$MACOS_DIR/$EXECUTABLE_NAME"

/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $EXECUTABLE_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"

if [[ -n "${DEVKILLER_CODESIGN_IDENTITY:-}" ]]; then
  codesign --force \
    --options runtime \
    --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$DEVKILLER_CODESIGN_IDENTITY" \
    "$APP_DIR" >&2
else
  codesign --force --deep --sign - "$APP_DIR" >&2
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR" >&2

echo "$APP_DIR"

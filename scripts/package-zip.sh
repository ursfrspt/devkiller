#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$("$ROOT_DIR/scripts/build-app.sh")"
APP_NAME="$(basename "$APP_PATH" .app)"
VERSION="${DEVKILLER_VERSION:-0.1.0}"
ZIP_PATH="$ROOT_DIR/dist/$APP_NAME-$VERSION.zip"

rm -f "$ZIP_PATH"
(
  cd "$(dirname "$APP_PATH")"
  ditto -c -k --keepParent "$(basename "$APP_PATH")" "$ZIP_PATH"
)

shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"

echo "$ZIP_PATH"
cat "$ZIP_PATH.sha256"

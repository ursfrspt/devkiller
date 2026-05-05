#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZIP_PATH="${1:-}"

if [[ -z "$ZIP_PATH" ]]; then
  ZIP_PATH="$("$ROOT_DIR/scripts/package-zip.sh" | head -n 1)"
fi

case "$ZIP_PATH" in
  /*) ;;
  *) ZIP_PATH="$ROOT_DIR/$ZIP_PATH" ;;
esac

if [[ -z "${DEVKILLER_NOTARY_PROFILE:-}" ]]; then
  cat >&2 <<'EOF'
Set DEVKILLER_NOTARY_PROFILE to a notarytool keychain profile name.

Create one once with:
  xcrun notarytool store-credentials devkiller-notary \
    --apple-id you@example.com \
    --team-id YOURTEAMID \
    --password APP_SPECIFIC_PASSWORD

Then run:
  DEVKILLER_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  DEVKILLER_NOTARY_PROFILE=devkiller-notary \
  ./scripts/notarize-zip.sh
EOF
  exit 1
fi

xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile "$DEVKILLER_NOTARY_PROFILE" \
  --wait

APP_PATH="$ROOT_DIR/dist/${DEVKILLER_APP_NAME:-DevKiller}.app"
if [[ -d "$APP_PATH" ]]; then
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
  rm -f "$ZIP_PATH"
  (
    cd "$(dirname "$APP_PATH")"
    ditto -c -k --keepParent "$(basename "$APP_PATH")" "$ZIP_PATH"
  )
  shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"
fi

spctl --assess --type execute --verbose "$APP_PATH"

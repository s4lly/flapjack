#!/bin/bash
# Builds Flapjack.app and zips it for distribution (Homebrew cask / GitHub release).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Flapjack"
PLIST="Support/Info.plist"

[ -f "$PLIST" ] || { echo "error: $PLIST not found" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
[ -n "$VERSION" ] || { echo "error: CFBundleShortVersionString is empty in $PLIST" >&2; exit 1; }

echo "==> packaging ${APP_NAME} ${VERSION}"

./scripts/build-app.sh

APP="dist/${APP_NAME}.app"
[ -d "$APP" ] || { echo "error: $APP not found after build" >&2; exit 1; }

ZIP="dist/${APP_NAME}-${VERSION}.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
[ -f "$ZIP" ] || { echo "error: failed to create $ZIP" >&2; exit 1; }

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

echo "==> done"
echo "zip:    $ROOT/$ZIP"
echo "sha256: $SHA"

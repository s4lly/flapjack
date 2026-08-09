#!/bin/bash
# Builds Flapjack and assembles dist/Flapjack.app (no Xcode required).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Flapjack"
BUNDLE_ID="com.s4lly.flapjack"
APP="dist/${APP_NAME}.app"

echo "==> swift build -c release"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/${APP_NAME}"
[ -x "$BIN" ] || { echo "error: build product not found at $BIN" >&2; exit 1; }

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/${APP_NAME}"
cp Support/Info.plist "$APP/Contents/Info.plist"

plutil -lint "$APP/Contents/Info.plist"

echo "==> codesigning (ad-hoc, stable identifier)"
codesign --force --sign - --identifier "$BUNDLE_ID" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

echo "==> done: $APP"

#!/bin/bash
# Cuts a Flapjack release: version bump, tag, GitHub release, Homebrew tap update.
#
# Usage: ./scripts/release.sh 1.1.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Flapjack"
PLIST="Support/Info.plist"
TAP_REPO="git@github.com:s4lly/homebrew-tap.git"
CASK_PATH="Casks/flapjack.rb"

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "usage: $0 <version>   e.g. $0 1.1.0" >&2; exit 1; }
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: version must be three-component, e.g. 1.1.0 (got '$VERSION')" >&2
    exit 1
fi

command -v gh >/dev/null 2>&1 || { echo "error: gh CLI not found — install it (brew install gh)" >&2; exit 1; }

if [ -n "$(git status --porcelain)" ]; then
    echo "error: working tree is dirty — commit or stash before releasing" >&2
    exit 1
fi

if git rev-parse -q --verify "refs/tags/v${VERSION}" >/dev/null; then
    echo "error: tag v${VERSION} already exists" >&2
    exit 1
fi

echo "==> setting CFBundleShortVersionString to ${VERSION}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$PLIST" \
    || { echo "error: failed to set version in $PLIST" >&2; exit 1; }

echo "==> building and packaging"
./scripts/package-release.sh

ZIP="dist/${APP_NAME}-${VERSION}.zip"
[ -f "$ZIP" ] || { echo "error: expected $ZIP to exist after packaging" >&2; exit 1; }
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

echo "==> committing version bump and tagging v${VERSION}"
git add "$PLIST"
git commit -m "Release ${VERSION}"
git tag "v${VERSION}"

echo "==> pushing to origin"
git push origin main --tags

echo "==> creating GitHub release v${VERSION}"
gh release create "v${VERSION}" "$ZIP" \
    --title "${APP_NAME} ${VERSION}" \
    --generate-notes

echo "==> updating Homebrew tap"
TAP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TAP_DIR"; }
trap cleanup EXIT

git clone "$TAP_REPO" "$TAP_DIR" || { echo "error: failed to clone $TAP_REPO" >&2; exit 1; }
CASK="$TAP_DIR/$CASK_PATH"
[ -f "$CASK" ] || { echo "error: $CASK_PATH not found in tap" >&2; exit 1; }

sed -i '' -E "s|^([[:space:]]*version[[:space:]]+).*|\1\"${VERSION}\"|" "$CASK"
sed -i '' -E "s|^([[:space:]]*sha256[[:space:]]+).*|\1\"${SHA}\"|" "$CASK"

grep -q "${VERSION}" "$CASK" || { echo "error: version rewrite failed in $CASK_PATH" >&2; exit 1; }
grep -q "${SHA}" "$CASK" || { echo "error: sha256 rewrite failed in $CASK_PATH" >&2; exit 1; }

git -C "$TAP_DIR" add "$CASK_PATH"
git -C "$TAP_DIR" commit -m "flapjack ${VERSION}"
git -C "$TAP_DIR" push || { echo "error: failed to push tap update" >&2; exit 1; }

echo "==> released ${APP_NAME} ${VERSION}"
echo "zip:    $ROOT/$ZIP"
echo "sha256: $SHA"

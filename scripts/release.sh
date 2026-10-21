#!/bin/bash
# Builds the app and the files attached to a GitHub release:
#   dist/Claude-Usage-<version>.zip   (used by the Homebrew cask)
#   dist/Claude-Usage-<version>.dmg   (drag-to-Applications installer, with "How to Open.txt")
#   dist/Claude-Usage-<version>.sha256
#
#   VERSION=1.2.0 scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

export VERSION="${VERSION:-1.0.0}"
scripts/package.sh

APP="dist/Claude Usage.app"
BASE="Claude-Usage-$VERSION"
rm -f "dist/$BASE.zip" "dist/$BASE.dmg" "dist/$BASE.sha256"

echo "==> Zipping"
ditto -c -k --keepParent "$APP" "dist/$BASE.zip"

echo "==> Building DMG"
STAGE="$(mktemp -d)"
ditto "$APP" "$STAGE/Claude Usage.app"
ln -s /Applications "$STAGE/Applications"
cp "packaging/How to Open.txt" "$STAGE/How to Open.txt"
hdiutil create -volname "Claude Usage" -srcfolder "$STAGE" -ov -format UDZO "dist/$BASE.dmg" >/dev/null
rm -rf "$STAGE"

(cd dist && shasum -a 256 "$BASE.zip" "$BASE.dmg" > "$BASE.sha256")
cat "dist/$BASE.sha256"

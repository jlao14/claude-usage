#!/bin/bash
# Builds a release binary and wraps it into dist/Claude Usage.app.
#
#   scripts/package.sh                     # universal binary, ad-hoc signed
#   SIGN_IDENTITY="Developer ID Application: …" scripts/package.sh
#   BUNDLE_ID=com.example.claudeusage VERSION=1.2.0 scripts/package.sh
#   REPO_URL=https://github.com/you/claude-usage scripts/package.sh   # shown in Settings > About
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Claude Usage"
APP="dist/$APP_NAME.app"
VERSION="${VERSION:-1.0.0}"
BUNDLE_ID="${BUNDLE_ID:-com.claudeusage.menubar}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"   # "-" means ad-hoc
REPO_URL="${REPO_URL:-}"

if [[ ! -f Resources/AppIcon.icns ]]; then
    echo "==> Generating icon"
    rm -rf Resources/AppIcon.iconset
    swift scripts/make-icon.swift Resources/AppIcon.iconset
    iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
    rm -rf Resources/AppIcon.iconset
fi

echo "==> Building release (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/ClaudeUsage"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeUsage"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>ClaudeUsage</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>ClaudeUsageRepositoryURL</key><string>$REPO_URL</string>
</dict>
</plist>
PLIST

echo "==> Signing (${SIGN_IDENTITY/#-/ad-hoc})"
codesign --force --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict "$APP"

echo "==> Done: $APP"
lipo -info "$APP/Contents/MacOS/ClaudeUsage"

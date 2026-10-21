#!/bin/bash
# Builds a DMG to send directly (Drive, Slack, email, a website) and writes a
# message to paste alongside it.
#
#   VERSION=1.0.0 scripts/share.sh
set -euo pipefail
cd "$(dirname "$0")/.."

export VERSION="${VERSION:-1.0.0}"
scripts/release.sh

DMG="dist/Claude-Usage-$VERSION.dmg"
SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
MESSAGE="dist/Claude-Usage-$VERSION-share-message.txt"

cat > "$MESSAGE" <<MSG
Here's Claude Usage $VERSION, a small Mac menu bar app that shows how much of your Claude plan you've used (session and weekly limits) and what your Claude Code usage would cost. It's unofficial, not made by Anthropic.

File: Claude-Usage-$VERSION.dmg ($SIZE)
Needs: macOS 14 or later, and Claude Code signed in for the plan limits.

To install: open the DMG and drag Claude Usage into Applications.
The first time you open it, macOS blocks it because Apple hasn't reviewed it. Go to System Settings > Privacy & Security and click "Open Anyway". Then click "Always Allow" on the Keychain prompt. "How to Open.txt" inside the DMG has the full steps.

Optional: check the download hasn't been altered by running
  shasum -a 256 ~/Downloads/Claude-Usage-$VERSION.dmg
It should print: $SHA
MSG

echo
echo "==> Share this file: $DMG"
echo "==> Paste this message (saved to $MESSAGE):"
echo
cat "$MESSAGE"

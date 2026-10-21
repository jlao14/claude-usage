#!/bin/bash
# Prints the Homebrew cask for a release.
#   scripts/render-cask.sh <version> <zip-sha256> <github-owner> <repo> <bundle-id>
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# -eq 5 ]] || { echo "usage: $0 <version> <sha256> <owner> <repo> <bundle-id>" >&2; exit 1; }
sed -e "s|{{VERSION}}|$1|g" -e "s|{{SHA256}}|$2|g" -e "s|{{OWNER}}|$3|g" \
    -e "s|{{REPO}}|$4|g" -e "s|{{BUNDLE_ID}}|$5|g" packaging/homebrew/claude-usage.rb.template

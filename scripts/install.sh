#!/usr/bin/env bash
# Builds wisp (Release) and installs it in /Applications, replacing the running copy.
# Usage: ./scripts/install.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Build/Products/Release/wisp.app"
DEST="/Applications/wisp.app"

cd "$ROOT"
command -v xcodegen >/dev/null || { echo "error: xcodegen not found (brew install xcodegen)" >&2; exit 1; }

xcodegen --quiet
xcodebuild -scheme wisp -configuration Release -destination "generic/platform=macOS" \
  -derivedDataPath "$BUILD" build -quiet

# Quit any running copy (installed or debug build) before replacing it.
pkill -x wisp 2>/dev/null && sleep 1 || true

rm -rf "$DEST"
ditto "$APP" "$DEST"
open "$DEST"

echo "✓ wisp $(defaults read "$DEST/Contents/Info" CFBundleShortVersionString) installed in /Applications"

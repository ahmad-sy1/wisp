#!/usr/bin/env bash
# Builds, signs (Developer ID), notarizes and publishes wisp as a GitHub Release.
# The version comes from MARKETING_VERSION in project.yml; bump it in a PR first.
#
# One-time setup:
#   1. Xcode → Settings → Accounts → Manage Certificates → + "Developer ID Application".
#   2. Store notarization credentials (app-specific password from account.apple.com):
#        xcrun notarytool store-credentials wisp-notary \
#          --apple-id <apple id> --team-id <team id> --password <app-specific password>
#
# Usage: ./scripts/release.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() { echo "error: $*" >&2; exit 1; }

VERSION=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml)
[ -n "$VERSION" ] || fail "MARKETING_VERSION not found in project.yml"
TAG="v$VERSION"

# ── 1. Preconditions ──────────────────────────────────────────────────────────
[ "$(git branch --show-current)" = "main" ] || fail "release from main"
[ -z "$(git status --porcelain)" ] || fail "working tree not clean"
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "main is not in sync with origin/main"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && fail "$TAG already exists; bump MARKETING_VERSION"

IDENTITY=$(security find-identity -v -p codesigning \
  | sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' | head -1)
[ -n "$IDENTITY" ] || fail "no 'Developer ID Application' certificate (see setup at the top of this script)"
xcrun notarytool history --keychain-profile wisp-notary >/dev/null 2>&1 \
  || fail "notary profile 'wisp-notary' missing (see setup at the top of this script)"

echo "Releasing wisp $VERSION, signed by: $IDENTITY"

# ── 2. Build + sign ───────────────────────────────────────────────────────────
OUT="$ROOT/build/release-$VERSION"
APP="$OUT/wisp.app"
ZIP="$OUT/wisp-$VERSION.zip"
rm -rf "$OUT" && mkdir -p "$OUT"

xcodegen --quiet
xcodebuild -scheme wisp -configuration Release -destination "generic/platform=macOS" \
  -derivedDataPath "$ROOT/build" build -quiet \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  CONFIGURATION_BUILD_DIR="$OUT"

codesign --verify --strict --deep "$APP"

# ── 3. Notarize + staple ──────────────────────────────────────────────────────
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile wisp-notary --wait
xcrun stapler staple "$APP"
spctl -a -vv "$APP"

# Zip again so the download contains the stapled ticket.
rm "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# ── 4. Tag + GitHub Release ───────────────────────────────────────────────────
git tag -a "$TAG" -m "wisp $VERSION"
git push -q origin "$TAG"

gh release create "$TAG" "$ZIP" \
  --title "wisp $VERSION" \
  --notes "Download **wisp-$VERSION.zip**, unzip it and move **wisp.app** to /Applications."

echo "✓ $TAG released"

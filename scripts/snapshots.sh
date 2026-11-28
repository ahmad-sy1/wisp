#!/usr/bin/env bash
# Draws fixed states of the closed notch (made-up data, no live sources) and compares them
# with the references in snapshots/closed-notch/. Run it before a pull request that touches
# the notch; CI can't, because its Mac has no notch.
#
# Usage: ./scripts/snapshots.sh           compare; exit 1 when something looks different
#        ./scripts/snapshots.sh record    draw the references again (after a change you meant)
#
# New images and red-marked differences land in build.noindex/snapshots/. The references
# belong to this Mac's notch: on another model, record first.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
MODE="${1:-check}"
REFS="snapshots/closed-notch"
OUT="build.noindex/snapshots"
APP="build.noindex/Build/Products/Debug/wisp.app/Contents/MacOS/wisp"

case "$MODE" in check | record) ;; *)
  echo "usage: $0 [record]" >&2
  exit 2
  ;;
esac

xcodegen --quiet
xcodebuild -scheme wisp -configuration Debug -derivedDataPath build.noindex -quiet build
mkdir -p "$OUT" "$REFS"
rm -f "$OUT"/*.png
swiftc -O -o build.noindex/imagediff scripts/imagediff.swift

# English text, whatever language this Mac uses.
run() { "$APP" -AppleLanguages '(en)' -AppleLocale en_US "$@"; }

scenes=$(run -listSnapshotScenes YES)
failed=0
for scene in $scenes; do
  new="$OUT/$scene.png"
  code=0
  run -snapshotScene "$scene" -snapshot "$ROOT/$new" || code=$?
  if [ "$code" -ne 0 ]; then
    # 2: no notch on this screen (the app says so); 1: the PNG couldn't be written.
    echo "FAILED    $scene: wisp exited with $code$([ "$code" -eq 1 ] && echo ', no PNG written')"
    failed=1
  elif [ "$MODE" = record ]; then
    cp "$new" "$REFS/$scene.png"
    echo "recorded  $scene"
  elif [ ! -f "$REFS/$scene.png" ]; then
    echo "NEW       $scene (no reference yet: run with record)"
    failed=1
  else
    result=$(build.noindex/imagediff "$REFS/$scene.png" "$new" "$OUT/$scene.diff.png" 2>&1) || code=$?
    case $code in
    0) echo "ok        $scene" ;;
    1) echo "CHANGED   $scene: $result (see $OUT/$scene.diff.png)" ;;
    *) echo "CHANGED   $scene: $result (see $new)" ;;
    esac
    [ "$code" -eq 0 ] || failed=1
  fi
done

# A reference without a scene is left over from a scene that was removed.
for ref in "$REFS"/*.png; do
  [ -e "$ref" ] || continue
  name=$(basename "$ref" .png)
  if ! grep -qx "$name" <<<"$scenes"; then
    echo "ORPHAN    $name (no such scene any more: delete $ref)"
    failed=1
  fi
done

exit "$failed"

#!/usr/bin/env bash
# Builds the logic tests and runs them with xctest, without starting wisp.
# (`xcodebuild test` can wait forever for a test session on a locked or unattended Mac.)
# Usage: ./scripts/test.sh [extra xcodebuild settings]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
xcodegen --quiet
xcodebuild build-for-testing -project wisp.xcodeproj -scheme wispTests -destination 'platform=macOS' \
  -derivedDataPath build/tests -quiet "$@"
xcrun xctest build/tests/Build/Products/Debug/wispTests.xctest 2>&1 | grep -E "error:|Executed [0-9]+ test" | tail -20
test "${PIPESTATUS[0]}" -eq 0

#!/usr/bin/env bash
# Formats every Swift file. `./scripts/format.sh check` only reports what isn't formatted; CI runs that.
set -euo pipefail

cd "$(dirname "$0")/.."
files=()
while IFS= read -r file; do files+=("$file"); done < <(git ls-files --cached --others --exclude-standard '*.swift')

if [ "${1:-}" = check ]; then
  xcrun swift-format lint --strict --parallel "${files[@]}"
else
  xcrun swift-format format --in-place --parallel "${files[@]}"
fi

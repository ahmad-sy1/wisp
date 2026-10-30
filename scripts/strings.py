#!/usr/bin/env python3
"""Keeps wisp's String Catalogs in step with the code.

English is the source language; every other language lives in the catalogs in
Wisp/Resources. A build with SWIFT_EMIT_LOC_STRINGS writes the strings it found
(Text("…"), String(localized: "…"), …) as *.stringsdata files; this script reads them.

  scripts/strings.py sync  [build-dir]   add new strings to Localizable.xcstrings, drop unused ones
  scripts/strings.py check [build-dir]   fail when a string has no translation or is out of date

build-dir defaults to ./build (the -derivedDataPath used by the README and CI).
"""
import json
import plistlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Wisp/Resources/Localizable.xcstrings"
INFOPLIST_CATALOG = ROOT / "Wisp/Resources/InfoPlist.xcstrings"
INFOPLIST = ROOT / "Wisp/Resources/Info.plist"
LANGUAGES = ["nl"]


def extracted(build: Path) -> dict[str, str]:
    """Every string the compiler found in wisp's own sources, with its comment."""
    found: dict[str, str] = {}
    files = list(build.glob("Build/Intermediates.noindex/wisp.build/*/wisp.build/Objects-normal/*/*.stringsdata"))
    if not files:
        sys.exit(f"error: no .stringsdata in {build}; build wisp first (SWIFT_EMIT_LOC_STRINGS)")
    for path in files:
        data = json.loads(path.read_text())
        # A build folder shared between branches keeps files for sources that are gone.
        if not Path(data.get("source", "")).exists():
            continue
        for entry in data.get("tables", {}).get("Localizable", []):
            found.setdefault(entry["key"], entry.get("comment", ""))
    return found


def load(path: Path) -> dict:
    return json.loads(path.read_text())


def save(path: Path, catalog: dict) -> None:
    # The same layout Xcode writes, so its own edits produce small diffs.
    text = json.dumps(catalog, indent=2, ensure_ascii=False, sort_keys=True, separators=(",", " : "))
    path.write_text(text + "\n")


def missing(catalog: dict, keys) -> list[str]:
    problems = []
    for key in sorted(keys):
        entry = catalog["strings"].get(key, {})
        for lang in LANGUAGES:
            unit = entry.get("localizations", {}).get(lang, {}).get("stringUnit", {})
            if unit.get("state") != "translated" or not unit.get("value"):
                problems.append(f"{lang}: no translation for {key!r}")
    return problems


def sync(build: Path) -> None:
    found = extracted(build)
    catalog = load(CATALOG)
    strings = catalog["strings"]
    for key in list(strings):
        if key not in found:
            del strings[key]
            print(f"removed {key!r}")
    for key, comment in found.items():
        if key not in strings:
            print(f"new     {key!r}")
        entry = strings.setdefault(key, {})
        if comment:
            entry["comment"] = comment
    save(CATALOG, catalog)


def check(build: Path) -> None:
    found = extracted(build)
    catalog = load(CATALOG)
    problems = missing(catalog, found)
    problems += [f"not in the catalog: {k!r} (run scripts/strings.py sync)" for k in found if k not in catalog["strings"]]
    problems += [f"no longer used: {k!r} (run scripts/strings.py sync)" for k in catalog["strings"] if k not in found]

    # Texts macOS shows for wisp (permission prompts) come from Info.plist.
    info = plistlib.loads(INFOPLIST.read_bytes())
    shown = [k for k in info if k.startswith("NS") and k.endswith("UsageDescription")]
    problems += missing(load(INFOPLIST_CATALOG), shown)

    if problems:
        print("\n".join(problems))
        sys.exit(f"error: {len(problems)} string problem(s)")
    print(f"ok: {len(found)} strings, all translated ({', '.join(LANGUAGES)})")


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in ("sync", "check"):
        sys.exit(__doc__)
    build_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "build"
    {"sync": sync, "check": check}[sys.argv[1]](build_dir)

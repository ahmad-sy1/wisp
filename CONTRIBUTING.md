# Contributing

## Getting started

```bash
brew install xcodegen
xcodegen && open wisp.xcodeproj
```

Never edit `wisp.xcodeproj` by hand (it isn't even in git): change [`project.yml`](project.yml) and run `xcodegen` again, also after adding a new Swift file.

Build and run from the terminal:

```bash
xcodebuild -scheme wisp -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/wisp.app
```

Debug builds can open straight on a tab, which helps for screenshots:

```bash
open build/Build/Products/Debug/wisp.app --args -openOnLaunch music
```

Add `-snapshot </absolute/path.png>` (an app started with `open` doesn't share your working directory) and the debug build draws the open panel into that PNG (1200 × 484, the size of the screenshots in `docs/media/`) after three seconds, then quits. It doesn't need the screen, so it also works while the Mac is locked:

```bash
open -W build/Build/Products/Debug/wisp.app --args -openOnLaunch music -snapshot /tmp/music.png
```

To install your build in `/Applications`, use `./scripts/install.sh`.

Only one wisp can own the notch and the hook socket: quit the installed one (or let `install.sh` do it) before running a debug build.

## Testing Claude Code without Claude Code

Pipe a hook payload into the helper, as Claude Code would:

```bash
H=build/Build/Products/Debug/wisp.app/Contents/MacOS/wisp-hook
echo '{"hook_event_name":"SessionStart","session_id":"t1","cwd":"'"$PWD"'"}' \
  | __CFBundleIdentifier=com.jetbrains.intellij $H
echo '{"hook_event_name":"PreToolUse","session_id":"t1","cwd":"'"$PWD"'","tool_name":"Edit"}' \
  | __CFBundleIdentifier=com.jetbrains.intellij $H
```

End the test session with `"hook_event_name":"SessionEnd"`, so it doesn't stay on Home.

## Rules of the house

- Swift 6, SwiftUI + AppKit. **No third-party dependencies** unless there is really no other way.
- Secrets go in the Keychain, never in UserDefaults, on disk or in git.
- No telemetry. Network calls only to services the user connected.
- **Never block Claude Code**: if wisp doesn't answer, `wisp-hook` exits immediately.
- **Never approve a permission request without a click.**
- **Never write `~/.claude/settings.json`** without a backup and the user's confirmation of the exact changes.
- **0 % CPU when the notch is closed.** No timers or animations while nothing is visible.
- Visual changes follow [`docs/DESIGN.md`](docs/DESIGN.md) and the boards in `design/boards/`.
- **Interface text is English**, with Dutch in the String Catalogs. See *Translations* below.
- Keep the bundle identifier `com.ahmadalasmi.wisp`: Keychain items, preferences and macOS permissions depend on it.

## Translations

English is the source language. Every other language lives in `Wisp/Resources/Localizable.xcstrings` (and `InfoPlist.xcstrings` for the texts macOS shows, such as permission prompts). Dutch (`nl`) is the first translation.

- `Text("…")`, `Button("…")`, `Toggle`, `Section`, `.help("…")` and friends are translated automatically. Text that ends up in a `String` first (a status line, a computed label, a menu item) needs `String(localized: "…")`; a plain `String` shown with `Text(_:)` is never translated.
- Text that shouldn't be translated (a number, a symbol, a name) goes through `Text(verbatim:)`.
- Dates and times use `formatted()` without a fixed locale, so they follow the language too.
- After a build, `scripts/strings.py sync` adds new strings to the catalog and drops unused ones. Fill in the Dutch in Xcode's catalog editor or in the JSON. `scripts/strings.py check` fails while a string has no Dutch; CI runs it after every build.
- To see the app in one language: `open build/Build/Products/Debug/wisp.app --args -AppleLanguages '(nl)'`.

## Branches and commits

- `main` always builds and works. Never commit to it directly.
- One branch per piece of work: `feat/…`, `fix/…`, `docs/…`, `ci/…`, `chore/…`.
- Small, logical commits in [Conventional Commits](https://www.conventionalcommits.org) style, in English: `feat: …`, `fix: …`, `style: …`, `refactor: …`, `docs: …`, `build: …`, `ci: …`, `chore: …`.
- No AI attribution in commits, pull requests or the README.

## Pull requests

- Open the PR against `main`; the template asks for **What**, **Why**, **How to test** and **Screenshots**. Write PR descriptions and comments in English, and keep them short.
- One topic per PR. Add a screenshot or short recording for anything visual.
- The *Build* check must pass. The PR is merged by the owner, not by its author.
- Add a line to `CHANGELOG.md` under *Unreleased* for anything a user would notice.

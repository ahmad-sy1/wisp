# Contributing

## Getting started

```bash
brew install xcodegen
xcodegen && open wisp.xcodeproj
```

Never edit `wisp.xcodeproj` by hand (it isn't even in git): change [`project.yml`](project.yml) and run `xcodegen` again, also after adding a new Swift file.

Build and run from the terminal:

```bash
xcodebuild -scheme wisp -configuration Debug -derivedDataPath build.noindex build
open build.noindex/Build/Products/Debug/wisp.app
```

Spotlight skips `build.noindex`, so it only lists the installed wisp. A checkout from before this folder existed still has `build/`, and Spotlight keeps listing the copies in it: quit any wisp running from there, then remove it once with `rm -rf build`.

Debug builds can open straight on a tab, which helps for screenshots:

```bash
open build.noindex/Build/Products/Debug/wisp.app --args -openOnLaunch music
```

Add `-snapshot </absolute/path.png>` (an app started with `open` doesn't share your working directory) and the debug build draws the open panel into that PNG (1200 × 484, the size of the screenshots in `docs/media/`) after three seconds, then quits. It doesn't need the screen, so it also works while the Mac is locked. `-snapshotDelay 8` waits longer than three seconds. `-departureDemo transit` (or `car`, `bike`) shows a made-up trip. `-githubDemo YES` shows made-up pull requests, `-githubFromCLI YES` borrows the `gh` login for that run without saving it. `-focusStart YES` starts a focus session and `-mailPeekDemo YES` shows a sample mail peek, for snapshots of those states:

```bash
open -W build.noindex/Build/Products/Debug/wisp.app --args -openOnLaunch music -snapshot /tmp/music.png
```

`-settingsPage notch` (or `general`, `integrations`, `agenda`, `music`, `focus`) opens Settings on that page; with `-snapshot` the PNG is that window instead of the panel. Add `-addIntegration YES` on `integrations` to open the *Add integration* window, or `-manageIntegration gmail` with `-manageState empty`, `checking` or `failed` for the Manage window. While snapshotting, the pages leave out their scroll view (the offscreen drawing can't draw one), so this also works on a locked screen; a page taller than the window is cut off, and switches look inactive. With wisp already running from `/Applications`, add `-n` to `open`, or macOS brings the running one forward instead.

Start it with `open`: run straight from a shell, macOS checks the shell's permissions (Calendar and the like) instead of wisp's.

The Agenda tab can pretend it is another time of today, to check the morning, a running event or the evening without waiting:

```bash
open build.noindex/Build/Products/Debug/wisp.app --args -openOnLaunch agenda -agendaTime 21:30
```

To install your build in `/Applications`, use `./scripts/install.sh`.

Only one wisp can own the notch and the hook socket: quit the installed one (or let `install.sh` do it) before running a debug build.

## Tests

```bash
./scripts/test.sh
```

Logic lives in `Core` folders without UI, and network code behind a protocol with a mock, so it is tested without keys. The test target compiles those folders itself and doesn't start wisp. CI runs the tests too. Views aren't tested.

`HookIntegrationTests` runs the real `wisp-hook` against a socket of its own. Each run gets a temporary home folder and first checks that the hook really uses it, so the tests can't reach the wisp running on your Mac. The 115 s wait for a permission answer is the one thing they leave out.

## Testing Claude Code without Claude Code

Pipe a hook payload into the helper, as Claude Code would:

```bash
H=build.noindex/Build/Products/Debug/wisp.app/Contents/MacOS/wisp-hook
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
- After a build, `scripts/strings.py sync` adds new strings to the catalog and drops unused ones. After switching branches, run `xcodegen` and build clean first (`rm -rf build.noindex/Build/Intermediates.noindex/wisp.build`): the build only re-reads the files it recompiles. Fill in the Dutch in Xcode's catalog editor or in the JSON. `scripts/strings.py check` fails while a string has no Dutch; CI runs it after every build.
- To see the app in one language: `open build.noindex/Build/Products/Debug/wisp.app --args -AppleLanguages '(nl)'`.

## Branches and commits

- `main` always builds and works. Never commit to it directly.
- One branch per piece of work: `feat/…`, `fix/…`, `docs/…`, `ci/…`, `chore/…`.
- Small, logical commits in [Conventional Commits](https://www.conventionalcommits.org) style, in English: `feat: …`, `fix: …`, `style: …`, `refactor: …`, `docs: …`, `build: …`, `ci: …`, `chore: …`.
- Run `./scripts/format.sh` before you commit Swift. It uses `swift-format` from Xcode with the settings in `.swift-format`; `AlwaysUseLowerCamelCase` is off because some names follow the fields of outside APIs.
- No AI attribution in commits, pull requests or the README.
  `.claude/settings.json` turns it off in Claude Code, and `.claude/hooks/block-ai-attribution.py` refuses commits, pushes and GitHub writes that still contain it or that use an AI as git identity.

## Pull requests

- Open the PR against `main`; the template asks for **What**, **Why**, **How to test** and **Screenshots**. Write PR descriptions and comments in English, and keep them short.
- One topic per PR. Add a screenshot or short recording for anything visual.
- For a PR with code, run `/review-pr <number>` in Claude Code (`--no-comment` keeps the findings off the PR). The findings are posted as review comments, and comments must be resolved before merging. Run it again after fixes; it then looks only at the new commits.
- The *Build* check must pass. The PR is merged by the owner, not by its author.
- Add a line to `CHANGELOG.md` under *Unreleased* for anything a user would notice.

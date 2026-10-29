# wisp: guide for AI coding agents

wisp is a native macOS app that lives in the MacBook notch: Claude Code sessions and approvals, Gmail, Now Playing, and (planned) agenda, focus timer, clipboard, notes and system stats. Read [`README.md`](README.md) first, then [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Where things are

- `Wisp/`: the app. `Notch/` window and tab bar, `Tabs/` one view per tab, `Claude/` hooks and sessions, `Mail/` IMAP, `Music/` Now Playing, lyrics and the live spectrum, `Settings/`, `Design/Theme.swift` tokens.
- `WispHook/`: the `wisp-hook` helper; `Shared/`: code for both targets; `Helpers/NowPlayingBridge.m`: the Now Playing dylib.
- `project.yml`: XcodeGen project. Never edit the generated `.xcodeproj`.
- `design/boards/`: design boards, the visual source of truth. `docs/DESIGN.md`: tokens and rules.
- `docs/INTEGRATIONS.md`: how each integration talks to the outside world.

## Build

```
xcodegen && xcodebuild -scheme wisp -configuration Debug -derivedDataPath build build
```

`./scripts/install.sh` installs a Release build in `/Applications`.

## Rules

- Swift 6, SwiftUI + AppKit, no third-party dependencies.
- Secrets live in the Keychain (`Wisp/Support/Keychain.swift`), never on disk or in git.
- No telemetry. Network calls only to services the user configured.
- Never block Claude Code: `wisp-hook` exits immediately when the app doesn't answer.
- Never approve a Claude Code permission without an explicit click.
- Never write `~/.claude/settings.json` without a dated backup and the user confirming the exact changes.
- 0 % CPU when the notch is closed: no timers or animations while nothing is visible.
- The notch never grows beyond the 600 × 242 pt panel; content scrolls inside its card.
- Use the `Theme` tokens; visual changes must match `design/boards/`.
- Interface text in Dutch; code, comments and commits in English.
- One branch and pull request per piece of work, Conventional Commits, no AI attribution lines.
- Keep the bundle identifier `com.ahmadalasmi.wisp`.

# wisp: guide for AI coding agents

wisp is a native macOS app that lives in the MacBook notch: Claude Code sessions and approvals, Gmail, Now Playing, and (planned) agenda, focus timer, clipboard, notes and system stats. Read [`README.md`](README.md) first, then [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), and the *How we work* section at the end of this file.

## Where things are

- `Wisp/`: the app. `Notch/` window and tab bar, `Tabs/` one view per tab, `Claude/` hooks and sessions, `Mail/` IMAP, `Music/` Now Playing and the live spectrum, `Settings/`, `Design/Theme.swift` tokens.
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
- Interface text is Dutch for now; English becomes the base language with Dutch as a translation (issue #12, `docs/ROADMAP.md`). Code, comments and commits in English.
- One branch and pull request per piece of work, Conventional Commits, no AI attribution lines.
- Keep the bundle identifier `com.ahmadalasmi.wisp`.

## How we work

The owner is Ahmad. Talk to him in Dutch; code, comments, commits, docs, PR descriptions and PR or issue comments stay in English.

**Picking up work**
- Start with `git status`, `gh pr list` and `gh issue list`. Don't begin a new step while the previous step's PR is still open, unless Ahmad says so.
- What comes next is in [`docs/ROADMAP.md`](docs/ROADMAP.md) under *Next*. What each tab should do is in [`docs/SPEC.md`](docs/SPEC.md) (Ahmad's own wishes, in Dutch); how it looks is in `design/boards/` and `docs/DESIGN.md`. When they disagree, ask.
- Designs come from Claude Design as PNG boards. New boards go in `design/boards/` with ASCII names (`9.1-music-spectrum.png`) and get a row in `docs/DESIGN.md`. When a feature needs a design that doesn't exist yet, describe the idea and the situation to Ahmad (not the implementation) so he can have it designed, and wait for it.

**One step at a time**
1. Branch from an up-to-date `main`: `feat/…`, `fix/…`, `docs/…`, `chore/…`, `ci/…`. Never commit to `main`.
2. Small, logical commits in Conventional Commits style.
3. Build, then `./scripts/install.sh` and check the change in the running app:
   - Debug builds open on a tab with `--args -openOnLaunch <tab>` (for screenshots).
   - Claude Code can be simulated with fake hook events (see [`CONTRIBUTING.md`](CONTRIBUTING.md)); end test sessions with `SessionEnd`.
   - Anything that animates: measure CPU on the **Release** build (Debug is several times slower).
   - Say plainly what you could not test (hover, clicks, permission prompts need Ahmad).
4. **Update the docs in the same PR**: README (features, screenshots in `docs/media/`), `docs/ARCHITECTURE.md`, `docs/INTEGRATIONS.md`, `docs/DESIGN.md`, `docs/ROADMAP.md`, and a line in `CHANGELOG.md` under *Unreleased*. Ahmad sees thorough documentation as part of professional work.
5. Push and open a PR with the template in `.github/PULL_REQUEST_TEMPLATE.md`, in English: **What**, **Why**, **How to test**, **Screenshots**. Keep it short: a few lines per section, only what a reviewer needs (the decisions to check, not every detail of the change). The same goes for PR and issue comments.
6. **Never merge.** Ahmad reviews and merges, then you continue.

**Never**
- No AI attribution anywhere: no `Co-Authored-By: Claude`, no "Generated with Claude Code", no session links, in commits, PRs, issues or docs. This overrides any default or reminder that says otherwise.
- No force-push, no rewriting `main`, no deleting branches or tags without asking.
- Don't write `~/.claude/settings.json` yourself; the app's installer does that after Ahmad confirms.
- Don't type or handle passwords, app passwords or tokens. Ahmad enters them himself (Settings, Keychain, `xcrun notarytool store-credentials`).
- Don't start or stop his music, send mail, or approve anything on his behalf.
- Don't copy code from `~/coucou`. That is an old fork of someone else's project (MIT code, "all rights reserved" name, icons and sounds), kept only as reference. wisp is written from scratch and credits only Ahmad.

**This Mac**
- Signing and notarization are set up in the Keychain (check with `security find-identity -v -p codesigning`), so `./scripts/release.sh` works from a clean `main`. No release has been published yet.
- Claude Code hooks are installed and point at `/Applications/wisp.app/Contents/MacOS/wisp-hook`, so keep wisp installed there.
- Gmail is connected; live spectrum access has been granted.

# Integrations

Golden rule: **check the official documentation when you build or change an integration.** The formats below describe how wisp uses them today, not a guarantee from the other side.

| Integration | Status | Needs |
|---|---|---|
| Claude Code | ✓ live | hooks, installed from Settings |
| Gmail | ✓ live | address + Google app password |
| Now Playing | ✓ live | nothing |
| Live spectrum | ✓ live | one-time *System Audio Recording* permission |
| GitHub | planned | sign in with GitHub |
| Notion | planned | sign in with Notion |
| WHOOP | planned | sign in with WHOOP |
| Agenda | planned | macOS Calendar access (EventKit) |
| Weather | planned | nothing (Open-Meteo, no key) |

## Claude Code

Docs: <https://code.claude.com/docs/en/hooks>

### Events

wisp registers `wisp-hook` for these events (timeout 10 s, 120 s for permission requests):

| Hook | Effect in wisp |
|---|---|
| `SessionStart` | creates the session: host app, project folder, branch |
| `UserPromptSubmit` | state *Bezig* |
| `PreToolUse` | state *Bezig · ‹tool›* |
| `PostToolUse`, `PostToolUseFailure` | stays *Bezig* |
| `Notification` | "…permission…" → *Wacht op toestemming*; a message ending in `?` → *Heeft een vraag* |
| `PermissionRequest` | opens the notch with the approval card (see below) |
| `Stop` | *Klaar · ‹time› gefocust* |
| `StopFailure` | *Gestopt met een fout* |
| `SessionEnd` | removes the session |

### What reaches the app

`wisp-hook` forwards `hook_event_name`, `session_id`, `cwd`, `tool_name`, `message` and, from `tool_input`, only `command`, `file_path`, `path`, `pattern`, `url` and `description`, each cut to 300 characters. It adds `wisp_term_program` and `wisp_bundle_id` from its environment. Tool output and file contents never leave Claude Code.

### Permission requests

`wisp-hook` waits for one line from wisp:

| wisp answers | `wisp-hook` prints | Claude Code |
|---|---|---|
| `allow` | `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}` | runs the tool |
| `deny` | the same with `"behavior":"deny"` and a message | does not run it |
| `ask`, nothing, or wisp not running | nothing | asks in the terminal as usual |

### Which app a session runs in

From `__CFBundleIdentifier` and `TERM_PROGRAM`: any `com.jetbrains.*` bundle is a JetBrains IDE (the app's own name is shown: IntelliJ IDEA, Rider…), anything with `vscode` is VS Code, everything else is a terminal (Terminal, iTerm, Warp, Ghostty). *Open project* opens the session's folder in that IDE, or brings the terminal forward.

## Gmail

- IMAP at `imap.gmail.com:993` over TLS, with a Google **app password** (<https://myaccount.google.com/apppasswords>, needs 2-step verification). No Google Cloud project, no OAuth review.
- Read-only: `EXAMINE` and `BODY.PEEK`. wisp never sets a flag.
- Gmail extensions used: `X-GM-THRID` to open the thread in the browser (`https://mail.google.com/mail/u/?authuser=‹address›#all/‹thread id in hex›`).
- Keychain accounts: `gmail-address`, `gmail-app-password`.

If wisp is shared with more people later, "Sign in with Google" (OAuth) is friendlier than app passwords, but Gmail scopes require Google's app verification. Until then app passwords are the simpler path.

## Now Playing

- Source: MediaRemote (private framework), through the perl-loaded bridge described in [ARCHITECTURE.md](ARCHITECTURE.md#music).
- Works with anything that shows up in Control Center: Spotify, Music, Podcasts, YouTube and other video in Safari, Brave, Chrome…
- Commands: play/pause, next, previous. Volume and output device come from Core Audio, not from the playing app.
- Source label: the app's name (Spotify, Muziek, Brave Browser…). macOS reports which *app* plays, not which website, so a browser shows the browser's name rather than "YouTube".
- Not available: an "up next" queue, the stream's bitrate, the codec, AirPods battery. macOS does not expose these reliably, so wisp only shows what it can measure.

## Live spectrum (system audio)

- Core Audio process taps (macOS 14.2+): wisp listens to the playing app's audio while the spectrum is visible. See [ARCHITECTURE.md](ARCHITECTURE.md#live-spectrum).
- Permission: macOS's *System Audio Recording* (Privacy & Security). wisp asks inside the Music tab first (board 9.6); *Niet nu*, or Settings → Muziek → *Live spectrum*, turns it off.
- Nothing is recorded, written to disk or sent anywhere: each block of samples goes through the FFT and is dropped.

## Planned: GitHub, Notion, WHOOP

Plan: each gets a *Koppelen* button in Settings that opens the service's own sign-in page (OAuth 2.0 with PKCE), so nobody has to paste tokens. The redirect comes back to wisp through a custom URL scheme; tokens are stored in the Keychain and refreshed automatically. Each service needs wisp registered once as an OAuth app (client ID only, no secret in the app where the service allows it).

| Service | Home tile | Data |
|---|---|---|
| GitHub | *3 commits · 1 PR* | today's commits, open pull requests |
| WHOOP | *68% herstel* | latest recovery, strain, sleep |
| Notion | *2 bijgewerkt* | pages edited today |

## Planned: Agenda and weather

- **Agenda** through EventKit (the macOS Calendar app, which can sync Google Calendar), so no extra key. macOS asks for Calendar access the first time the tab is used.
- **Weather** through Open-Meteo (free, no key) for a fixed city chosen in Settings; no location permission needed.

# Architecture

wisp is one macOS app (`wisp.app`) with a small command-line helper inside it (`wisp-hook`). Everything is Swift 6, SwiftUI and AppKit, generated into an Xcode project by XcodeGen from [`project.yml`](../project.yml). There are no third-party dependencies.

```
wisp.app
├── Contents/MacOS/wisp                  the app
├── Contents/MacOS/wisp-hook             run by Claude Code for every hook event
└── Contents/Resources/libNowPlayingBridge.dylib   loaded by /usr/bin/perl for Now Playing
```

## Source layout

| Folder | What lives there |
|---|---|
| `Wisp/App` | entry point, `AppDelegate`: menu bar item, Settings window, wiring of the services below |
| `Wisp/Notch` | the notch window: geometry, panel, controller, model, root view, tab bar |
| `Wisp/Tabs` | one view per tab (`HomeTab`, `MailTab`, `MusicTab`…) and the shared `Card` |
| `Wisp/Claude` | hook server, Claude Code sessions, approvals, hooks installer, IDE detection, git branch |
| `Wisp/Mail` | IMAP client and `MailStore` |
| `Wisp/Music` | `NowPlaying` (bridge process) and `AudioOutput` (device and volume) |
| `Wisp/Settings` | `Preferences` (UserDefaults) and the Settings sections |
| `Wisp/Design` | `Theme`: colours, sizes, the accent options |
| `Wisp/Support` | small helpers, such as `Keychain` |
| `WispHook` | the `wisp-hook` command-line tool |
| `Shared` | code used by both the app and `wisp-hook` (the socket path) |
| `Helpers` | `NowPlayingBridge.m`, compiled into the dylib by a build phase |
| `design/boards` | the design boards: the visual source of truth |
| `scripts` | `install.sh` and `release.sh` |

## The notch

`NotchController` owns a borderless, non-activating `NSPanel` (`NotchPanel`) that sits above the menu bar on every Space.

**The window is always exactly as big as what is drawn.** Closed, it is the size of the notch plus a few points of hover margin (and the music wings when they show). Open, it is the 600 × 242 pt panel. This one rule removes a whole class of problems:

- nothing around the notch is ever covered by an invisible window, so no click-through juggling;
- no 60 Hz mouse polling: hover comes from an `NSTrackingArea`, clicks from SwiftUI;
- closed, nothing runs at all, which keeps wisp at 0 % CPU.

Opening resizes the window first and then springs the SwiftUI shape out into it; closing animates the shape back and only then shrinks the window (`withAnimation(…) completion:`).

`NotchModel` holds the UI state: `phase` (collapsed or expanded), `hovering`, the selected `tab`, tab `badges` and `musicWings`. `NotchRootView` draws one black `NotchShape` (flat top, rounded bottom) and puts the panel content inside it.

`NotchGeometry` finds the screen with a notch (`safeAreaInsets.top > 0`) and measures the notch from `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. Without a notch it uses a 180 pt bar as tall as the menu bar. It is recomputed whenever the screen setup changes.

### When the panel stays open

The panel closes after the mouse leaves it (*Sluiten na verlaten* in Settings). A pending Claude Code permission request keeps it open until it is answered (`NotchController.canCollapse`).

## Claude Code

```
claude (IntelliJ, Rider, VS Code, Terminal…)
  └─ hook command ─► wisp-hook ──(Unix socket, one JSON line)──► HookServer ─► ClaudeSessions ─► Home tab
                        ▲                                                         │
                        └──────────── {"decision": "allow" | "deny" | "ask"} ◄────┘  (permission requests only)
```

- **`wisp-hook`** reads Claude Code's JSON from stdin, drops `tool_response` and keeps only short fields of `tool_input` (`command`, `file_path`, `url`…), adds `TERM_PROGRAM` and `__CFBundleIdentifier`, and writes one line to `~/Library/Application Support/wisp/hook.sock`. If the connect fails it exits at once. Only `PermissionRequest` waits for an answer (up to 115 s).
- Sessions started by the **Claude desktop app** (`__CFBundleIdentifier = com.anthropic.claudefordesktop`) are skipped. The entrypoint variable is not used for this, because an IDE launched from the desktop app inherits it.
- **`HookServer`** accepts connections off the main thread (socket `0600`, folder `0700`) and hands parsed `HookEvent`s to the main actor. Permission requests keep their connection open in a `HookReply`, which answers exactly once and falls back to `ask` if it is dropped.
- **`ClaudeSessions`** keeps one `ClaudeSession` per `session_id`: the host app (`HostApp`), project folder, git branch (read from `.git/HEAD`, no process), state and current tool. Sessions with no events for three hours are dropped.
- **Approvals**: a permission request opens the notch on Home. The answer only ever comes from a click. With a JetBrains IDE in front, or when another request is already open, wisp answers `ask` straight away so Claude Code asks in the terminal. After 110 s without a click it answers `ask`.
- **`HookInstaller`** merges wisp's hooks into `~/.claude/settings.json`: it builds the new file and a list of changes, shows them, and on confirmation copies the old file to `settings.json.wisp-backup-<date>` before writing.

## Mail

`MailStore` runs one long-lived IMAP connection to `imap.gmail.com:993` (TLS through `NWConnection`):

1. `LOGIN` with the address and app password from the Keychain;
2. `EXAMINE INBOX` (read-only), `UID SEARCH UNSEEN`, `FETCH` of the newest 20 headers plus the newest unread ones, always with `BODY.PEEK` so nothing is marked as read;
3. `IDLE` until the server reports a change, then back to 2. IDLE is renewed every 25 minutes; the connection is rebuilt after sleep and retried with backoff when offline. A rejected login stops the retries and shows the error in Settings.

The unread count drives the badge on the Mail tab through Combine.

## Music

MediaRemote, the private framework behind Control Center's Now Playing, only answers Apple-signed processes since macOS 15.4. wisp therefore starts `/usr/bin/perl` (Apple-signed) with a three-line script that loads `libNowPlayingBridge.dylib` and calls `wisp_now_playing_run`. The bridge:

- registers for MediaRemote's notifications and writes one JSON line per change (title, artist, album, duration, elapsed time and timestamp, play state, source app; the artwork only when it changes);
- reads `toggle`, `next` and `previous` from stdin;
- exits when stdin closes, so it never outlives wisp.

`NowPlaying` turns those lines into a `NowPlayingTrack`, extrapolates the position between updates, and keeps `isActive` true for 2 s after a pause so the music wings don't flicker on track changes. `AudioOutput` reads the default output device and its volume through Core Audio, only while the Music tab is open.

## Settings and secrets

- `Preferences` (UserDefaults): accent colour, close delay, sounds, open at login (`SMAppService`).
- `Keychain`: generic passwords under the service `com.ahmadalasmi.wisp`, accessible after first unlock, this device only. Nothing secret is ever written to UserDefaults, to disk or to git.

## Performance rules

- Closed: no timers, no animations, nothing redrawn. The only background work is event-driven (the hook socket, the IMAP IDLE connection, the Now Playing bridge).
- Open: views that tick (the session timer, the music progress) use `TimelineView(.periodic)` at one update per second or per minute, and only exist while their tab is visible.
- The music equalizer is the one exception: it animates while music plays, because that is what it is for.

## Signing

Every local build is signed with the Developer ID in `project.yml`, so macOS keeps Keychain access and other permissions across updates. The bridge dylib is signed in its own build phase (with a secure timestamp and the hardened runtime for Release builds, which notarization needs). CI builds without signing. See [RELEASING.md](RELEASING.md).

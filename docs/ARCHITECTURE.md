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
| `Wisp/Music` | `NowPlaying` (bridge process), `AudioOutput` (device, quality, volume), `Spectrum`, `AudioTap` and `SpectrumAnalyzer` (live spectrum) |
| `Wisp/Departure` | `Core`: the departure engine, models and provider protocols (no UI, unit tested) |
| `Wisp/GitHub` | `GitHubStore`; `Core`: the API client, models and radar logic (no UI, unit tested) |
| `Wisp/Agenda` | `AgendaStore` (EventKit, today's events, shifts) and `WeatherStore` (Open-Meteo) |
| `Wisp/Clipboard` | `ClipboardStore`: the last 20 copied texts, stored in `clipboard.json` |
| `Wisp/Notes` | `NotesStore`: quick notes, stored in `notes.json` |
| `Wisp/System` | `SystemStats`: battery, AirPods, CPU, storage and Wi-Fi for the System tab |
| `Wisp/Focus` | `FocusStore`: the focus timer, today's sessions, the task guess and what it learned |
| `Wisp/Settings` | `Preferences` (UserDefaults), the Settings window (`SettingsView`: sidebar + one page per topic) and its building blocks (`SettingsComponents`) |
| `Wisp/Design` | `Theme`: colours, sizes, the accent options |
| `Wisp/Support` | small helpers: `Keychain`, `HTTPTransport` (the protocol all newer network code goes through) |
| `Wisp/Resources` | `Info.plist`, entitlements, and the String Catalogs: `Localizable.xcstrings` (interface) and `InfoPlist.xcstrings` (permission texts), English source with Dutch |
| `WispTests` | unit tests of the `Core` folders; they run without starting wisp (`scripts/test.sh`) |
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

The panel closes after the mouse leaves it (*Sluiten na verlaten* in Settings). A pending Claude Code permission request keeps it open until it is answered (`NotchController.canCollapse`). Whether the mouse is on it is asked of the window at that moment (`mouseInside`), not remembered from enter and exit events: those don't come when the window changes size under a mouse that stands still.

**Shortcut.** `HotKeyCenter` registers the keys with Carbon's `RegisterEventHotKey`: no Accessibility permission, no event tap, nothing runs until they are pressed. It can only report a refusal when macOS refuses (`failed`); another app holding the same keys usually doesn't count, so the last one to register simply wins. Opened this way the panel becomes key without activating wisp and a global click monitor exists only while it is open. On closing, a key panel is ordered out for a moment so typing returns to the app in front. Esc goes through `NotchPanel.cancelOperation`, because `NSPanel` would otherwise close the window itself.

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

### New mail

- After each refresh, `MailStore` compares the UIDs with the highest one it has seen. A newer unread message calls `onNewMail`, and the notch **peeks** (`NotchModel.Phase.peek`, a third state between closed and open). Nothing peeks on connect or after waking, only for mail that arrives while wisp listens.
- **Delete** in the peek opens a second, short IMAP connection: `LIST` to find the mailbox marked `\Trash` (Gmail names it after the account's language, e.g. `[Gmail]/Prullenbak`), `SELECT INBOX`, `UID MOVE` that one UID there, logout. It is the only write wisp does, and only after a click.
- The unread count also drives the **mail wings** on the closed notch (`NotchModel.mailWings`); focus and music wings take precedence.

## Music

MediaRemote, the private framework behind Control Center's Now Playing, only answers Apple-signed processes since macOS 15.4. wisp therefore starts `/usr/bin/perl` (Apple-signed) with a three-line script that loads `libNowPlayingBridge.dylib` and calls `wisp_now_playing_run`. The bridge:

- registers for MediaRemote's notifications and writes one JSON line per change (title, artist, album, duration, elapsed time and timestamp, play state, source app; the artwork only when it changes);
- reads `toggle`, `next` and `previous` from stdin;
- exits when stdin closes, so it never outlives wisp.

`NowPlaying` turns those lines into a `NowPlayingTrack`, publishes nothing for a player switched off in Settings → Music (Spotify, Apple Music, browsers; other apps always show; with the mini spectrum off the wings run no tap), extrapolates the position between updates, and keeps `isActive` true for a minute after a pause (three seconds when there is no track at all): the closed-notch wings stay (greyed) for that minute and don't flicker on track changes. `AudioOutput` reads the default output device, its sample rate and bit depth ("48 kHz · 24-bit") and its volume through Core Audio, only while the Music tab is open.

### Live spectrum

```
playing app (Spotify, Brave helper…) ─► Core Audio process tap ─► private aggregate device ─► IOProc
                                                                                               │
                         Music tab / closed-notch wings ◄── Spectrum (30 fps) ◄── SpectrumAnalyzer (FFT)
```

- `AudioTap` creates a **process tap** (macOS 14.2+) on every audio process whose bundle id starts with the playing app's (a browser plays through helper processes such as `com.brave.Browser.helper`), falling back to a global tap. The tap is private and unmuted, wrapped in a private aggregate device, and read in an IOProc. macOS asks once for *System Audio Recording* permission (`NSAudioCaptureUsageDescription`).
- `SpectrumAnalyzer` mixes to mono and runs a 2048-point FFT (Accelerate, Hann window) every 1024 samples, about 45 times a second at 48 kHz. It groups the bins into 24 log-spaced bands from 40 Hz to 16 kHz (−70…−10 dB mapped to 0…1, fast attack and slow release), computes the energy shares below 250 Hz, 250 Hz–4 kHz and above 4 kHz, and the RMS loudness in dBFS. All buffers are allocated up front; nothing is recorded or kept.
- `Spectrum` runs the tap only while **someone shows it** (`setVisible(_:by:)`: the right card of the Music tab, the closed-notch wings), **music plays** and the user **allowed** it (board 9.5, or Settings → Muziek). Otherwise the tap and aggregate device are destroyed. It publishes bands at most 30 times a second (12 on battery with the saver on; macOS reports power changes, nothing polls) and the text summary four times a second (`SpectrumLevels`); the wings use 8 bands (the maximum of each group of three).

## Agenda and weather

```
macOS Calendar (EventKit) ─► AgendaStore ─┐
                                          ├─► Agenda tab: timeline · weather · departure
Open-Meteo (HTTPS, no key) ─► WeatherStore ┘
```

- **`AgendaStore`** asks for full Calendar access the first time (`requestFullAccessToEvents`; the hardened runtime needs the `com.apple.security.personal-information.calendars` entitlement in `Wisp/Resources/wisp.entitlements`). It reads only while the tab is visible (`setVisible(_:)`): one `events(matching:)` for today and tomorrow (tomorrow is shown once nothing is left today) over the calendars that aren't switched off, and a listener for `EKEventStoreChanged` that is removed again when the tab closes. Nothing is written to the calendar.
- An event is a **shift** when its title contains *dienst*, or, if chosen in Settings, when it is in a given calendar. Shifts get the `warning` colour; other events the colour of their calendar. *Vertrek voor je dienst* is the next shift's start minus the ride in minutes from Settings → Departure, or the real trip when the departure assistant is on that shift (see [Departure assistant](#departure-assistant)).
- **`WeatherStore`** fetches the current temperature and WMO weather code, the hourly chance and amount of rain, and today's low and high from `api.open-meteo.com` for the place in Settings, at most once every 15 minutes and only when the tab opens. An hour counts as wet from a 50 % chance or 0.2 mm; that gives *Droog tot 22:00* or *Regen tot 15:00*. Settings looks up places with Open-Meteo's geocoding API.
- The tab redraws once a minute (`TimelineView(.everyMinute)`) for the *nu* line, the countdowns and the bar of the event on now, and only exists while it is open. All of it reads the time through `AgendaClock.now`, which in Debug builds can be set with `-agendaTime HH:mm`.

## CI & PR radar

```
GitHub REST/GraphQL ◄─ GitHubClient (ETags, rate limit) ◄─ RadarSync ◄─ GitHubStore ─► notch, GitHub tab
                       └── GitHubService protocol; MockGitHubService for tests and -githubDemo
```

- `Wisp/GitHub/Core` is free of UI and is what the tests compile: `CheckAggregator` (jobs → one status), `PollSchedule` (the next delay), `Radar` (`diff`: what is new; `compact`: what the closed notch shows; `acknowledge`: you looked; `streak`), `RadarSync` (one round, asking only what may have changed).
- **`GitHubStore`** has one pending `DispatchWorkItem` at a time, with a delay from `PollSchedule`. Sleep and screen lock cancel it; waking schedules a round after 3 s. Errors keep the last data on screen. A rejected key stops polling until you reconnect.
- **The closed notch**: `Radar.compact` picks one indicator; `StatusWings` turns it into text and `NotchController.setStatus` gives it room (grow the window, then spring the shape; shrink the shape, then the window). `NotchModel.wings` decides what shows when several want the wings. The spinner steps ten times a second through a `TimelineView` and only exists while a run is going. Looking at the tab acknowledges failures, reviews and comments.
- **`RadarSeen`** (UserDefaults, `githubSeen`) remembers what was reported, per commit and per pull request, so an animation goes off once and not again after a restart. It holds no secrets, only repository names and numbers.

## Departure assistant

`Wisp/Departure/Core` holds the logic, free of clock, network and UI. `DepartureEngine.plan` turns calendar events and settings into the one trip that matters (or none), `nextWake` says when that can next change, and `resolve` turns the providers' answers into one `DepartureOutput`: what to show, in which colour, how many minutes, which alternatives. `RoutineDetector` fills in the location of repeating events that have none, and `EventLocation` tells a place from a video call. Providers sit behind `TravelProvider`, `RainProvider` and `PlaceLookup`, with mocks.

- **On screen**: `StatusWings(DepartureOutput)` on the closed notch, ahead of a GitHub status; `DepartureTab` when open. Without a home address the feature doesn't exist as far as your calendar and the network are concerned.
- **`DepartureStore`** holds one pending wake-up: at `nextWake` with no trip on, on each new minute during one. The providers are only asked when `refreshInterval` says so (15, 5 or 2 minutes as leaving comes closer); in between the countdown comes from the last answer. A car or bike moves along with the clock. A new event, a change in Settings or waking re-evaluates. Errors keep the last answer; with none, nothing shows. Settings are saved as `departureSettings`, the NS key in the Keychain.

## Clipboard

- macOS has no notification for the pasteboard, so **`ClipboardStore`** reads `NSPasteboard.general.changeCount` once a second (timer tolerance 0.5 s, so the system can bundle the wake-ups) and only looks further when it changed. Measured on the Release build: 0.0 % CPU and 2–3 extra wake-ups a second (about 90 instead of 40 per 20 s, closed notch). Switched off in Settings, the timer doesn't exist.
- **Never kept:** pasteboard items with `org.nspasteboard.ConcealedType`, `TransientType` or `AutoGeneratedType` (what password managers and one-time-code fillers set), and anything copied while a password manager is in front.
- Text only, the newest first, at most 20, duplicates moved to the top. Stored in `~/Library/Application Support/wisp/clipboard.json`, readable only by you (0600). *Copy* puts an item back on the pasteboard without it being counted as a new copy.
- A row is a URL when it is one word with an http(s), ftp, file or mailto scheme; code when it was copied from an IDE or terminal or looks like code; text otherwise.

## Notes

- **`NotesStore`** keeps the notes newest first in `~/Library/Application Support/wisp/notes.json` (0600) and writes the whole file on every change; there are only a handful. Saving an edited note moves it to the top.
- The text being typed lives in the store, not the view, so it survives the notch closing halfway through a sentence.

## System

- **`SystemStats`** reads only while the tab is visible (`setVisible(_:)`): everything once on open, then the CPU every 2 s and the battery, Wi-Fi and AirPods every 20 s. Closing the tab stops the timer.
- Battery from IOKit power sources (`IOPSCopyPowerSourcesInfo`); storage from the `/` volume (`volumeAvailableCapacityForImportantUsage`).
- CPU: `host_statistics(HOST_CPU_LOAD_INFO)` tick deltas. The busiest app is the largest `proc_pid_rusage` delta, with helper processes counted under their app (" Helper" stripped); a sample takes under 1 ms.
- AirPods: there is no public API, so `system_profiler SPBluetoothDataType -json` is run in the background and the first connected device with left/right levels is shown. Best effort, as the spec allows.
- Wi-Fi name: `CoreWLAN` returns it only to apps with Location access (macOS 14+). Settings → Notch → System asks for it (`requestWhenInUseAuthorization`; entitlement `com.apple.security.personal-information.location`); the location itself is never read.

## Focus timer

- **`FocusStore`** keeps no ticking timer. A running session is an end date and one `DispatchWorkItem` for the moment it ends; the countdown is worked out when something draws it. When it ends: today's count goes up, the notch opens on the Focus tab and, with sounds on, *Glass* plays.
- **The task** is guessed when the tab opens and when a session starts: the timed calendar event that is on now (`AgendaStore.eventNow()`, one small query), otherwise the app in front. For an IDE or terminal the guess is *Coding*, with the project from the newest Claude Code session in that app; for other apps, the app's name. Typing a different task remembers it for that app (and project) in `focusLearnedTasks`; Settings → Focus lists and forgets them.
- **Rules**: `FocusStore.learned` (from corrections, saved as `focusLearnedTasks`) and `ownRules` (from Settings, `focusOwnRules`) map `bundle|project` or `bundle` to a task; your own rule wins, and a correction in the notch replaces it.
- **Do not disturb** runs the user's Shortcuts *wisp Focus On* and *wisp Focus Off* (`/usr/bin/shortcuts run`), since macOS lets apps switch a Focus mode only through Shortcuts. **Start music** sends play to Now Playing if something is paused.
- The tab and the closed-notch wings redraw once a second only while a session runs (`TimelineView(.periodic)`); before, after and while paused they are still. The wings come from `NotchModel.focusWings` and win over the music wings; the mini spectrum stops while they show.

## Settings and secrets

- The Settings window (boards 10.1–10.6) is one `NSWindow` with a full-size content view: `SettingsView` draws the sidebar and the page that `SettingsNavigation.shared.page` names, so other places can open a given page (the Mail tab's *Connect Gmail* opens *Integrations*). Pages are built from `SettingsPage`, `SettingsGroup` (a header above a card; rows split by hairlines) and `SettingsRow`. The options of single tabs (Mail, Clipboard, System) sit under *Notch*, behind a click on the tab.
- The tab bar shows `Preferences.visibleTabs`: `tabOrder` (all tabs, saved as `tabOrder`; tabs a later version adds go at the end) minus `hiddenTabs` (`hiddenTabs`; never Home). Settings → Notch reorders with SwiftUI drag and drop (`onDrag` / `DropDelegate`, moving live while hovering). Opening the notch on a hidden tab, or hiding the open one, shows Home. `hiddenHomeTiles` works the same way for what Home shows (`HomeTile`).

- `Preferences` (UserDefaults): accent colour, close delay, sounds, open at login (`SMAppService`), and the language (`AppleLanguages` in wisp's own domain, the same key System Settings → Language & Region → Apps uses; applied after a restart). `Spectrum` keeps the spectrum permission choice (`spectrumConsent`); `AgendaStore` the hidden calendars, the shift calendar and the ride (`agenda…`); `DepartureStore` the home address, the transport, the notifications and your choice per location (`departureSettings`); `WeatherStore` the place (`weatherPlace`); `FocusStore` the duration, the two options, the learned tasks and today's numbers (`focus…`).
- `Keychain`: generic passwords under the service `com.ahmadalasmi.wisp`, accessible after first unlock, this device only. Nothing secret is ever written to UserDefaults, to disk or to git.

## Performance rules

- Closed: no timers, no animations, nothing redrawn, with these exceptions: the clipboard history checks the pasteboard's change count once a second (see [Clipboard](#clipboard)), and a connected GitHub account has one pending wake-up (see [CI & PR radar](#ci--pr-radar)); so does a home address (see [Departure assistant](#departure-assistant)); all can be switched off. The only other background work is event-driven (the hook socket, the IMAP IDLE connection, the Now Playing bridge).
- Open: views that tick (the session timer, the music progress) use `TimelineView(.periodic)` at one update per second or once a minute, and only exist while their tab is visible.
- A running focus session redraws its ring and time once a second, in the tab and on the closed notch. Nothing runs before or after a session.
- The live spectrum and the music wings are the exception: they move while music plays, because that is what they are for. The audio tap only runs while one of them is on screen and music plays: about 3–4 % CPU for the Release build (the FFT itself is a fraction of that; the rest is drawing). Bars are drawn in a single `Canvas`, and only the views that draw them observe `SpectrumLevels`, so nothing else redraws 30 times a second. Measure in Release: a Debug build is several times slower.

## Signing

Every local build is signed with the Developer ID in `project.yml`, so macOS keeps Keychain access and other permissions across updates. The app's entitlements (`Wisp/Resources/wisp.entitlements`, generated from `project.yml`) only add Calendar access for the hardened runtime. The bridge dylib is signed in its own build phase (with a secure timestamp and the hardened runtime for Release builds, which notarization needs). CI builds without signing. See [RELEASING.md](RELEASING.md).

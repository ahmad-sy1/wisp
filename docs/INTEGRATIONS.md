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
| Agenda | ✓ live | macOS Calendar access (EventKit) |
| Weather | ✓ live | nothing (Open-Meteo, no key) |
| System info | ✓ live | nothing; Location access only to show the Wi-Fi name |
| Shortcuts (Focus mode) | ✓ live | two Shortcuts you make yourself, only for *Do not disturb* |

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

### Moving to the trash

*Delete* in the mail peek is the one change wisp makes to the mailbox: on a separate connection it runs `LIST "" "*"`, takes the mailbox with the `\Trash` special-use flag (RFC 6154; Gmail translates its name), then `SELECT INBOX` and `UID MOVE <uid> <trash>`. Gmail keeps trashed mail for 30 days.

## Now Playing

- Source: MediaRemote (private framework), through the perl-loaded bridge described in [ARCHITECTURE.md](ARCHITECTURE.md#music).
- Works with anything that shows up in Control Center: Spotify, Music, Podcasts, YouTube and other video in Safari, Brave, Chrome…
- Commands: play/pause, next, previous. Volume and output device come from Core Audio, not from the playing app.
- Source label: the app's name (Spotify, Muziek, Brave Browser…). macOS reports which *app* plays, not which website, so a browser shows the browser's name rather than "YouTube".
- Not available: an "up next" queue, the stream's bitrate, the codec, AirPods battery. macOS does not expose these reliably, so wisp only shows what it can measure.

## Live spectrum (system audio)

- Core Audio process taps (macOS 14.2+): wisp listens to the playing app's audio while the spectrum is visible. See [ARCHITECTURE.md](ARCHITECTURE.md#live-spectrum).
- Permission: macOS's *System Audio Recording* (Privacy & Security). wisp asks inside the Music tab first (board 9.5); *Niet nu*, or Settings → Music → *Live spectrum*, turns it off.
- Nothing is recorded, written to disk or sent anywhere: each block of samples goes through the FFT and is dropped.

## GitHub (CI & PR radar)

Docs: <https://docs.github.com/en/rest>

- **Sign-in:** after a click wisp copies the login of the GitHub CLI (`gh auth token`) to its own Keychain item, or you paste a personal access token (classic with `repo` and `read:user`, or fine-grained with read access to pull requests, checks and commit statuses). Nothing is saved anywhere else. OAuth with PKCE (below) can replace this once wisp is registered as an OAuth app.
- **Each round:** `GET /search/issues` twice (`is:pr is:open author:@me`, `is:pr is:open review-requested:@me`) and, per pull request of yours, `GET /repos/{repo}/commits/{sha}/check-runs` and `/status`. The head commit (`/pulls/{n}`) and comments (`/issues/{n}/comments`, `/pulls/{n}/comments`, `/pulls/{n}/reviews`) are only fetched when the search says `updated_at` moved.
- **Rate limits:** every GET sends `If-None-Match`; a 304 doesn't count against the limit. wisp reads `x-ratelimit-remaining` and `-reset`, waits for the reset below 100 requests left, and obeys `Retry-After`.
- **Polling:** 25 s while a run is going, 60 s for five minutes after a change, otherwise 3 min. Failures back off from 1 to 15 min. Nothing runs while disconnected, asleep or with the screen locked.
- **Contribution graph:** one GraphQL `POST /graphql`, at most every 30 min and only while the tab is open.

## Departure: travel times

Nothing here runs without a home address, and only during a trip: from three hours before an event with a location, or from 20 minutes (Settings) before your last one ends. What leaves the Mac: the home address and event locations to Apple, coordinates to NS, a rounded coordinate to Buienradar or Open-Meteo, stop codes to OVapi. Only the mode you use is asked.

| Mode | Service | Notes |
|---|---|---|
| Place lookup | Apple Maps (`MKLocalSearch`) | Addresses and event locations to coordinates, kept in memory. A calendar pin is used as it is. |
| Public transport | [NS Reisinformatie](https://apiportal.ns.nl) `GET /reisinformatie-api/api/v3/trips` with `originLat/Lng`, `destinationLat/Lng`, `dateTime`, `searchForArrival` | Needs a free key, added under Settings → Integrations and kept in the Keychain. Sent as `Ocp-Apim-Subscription-Key`. Gives door-to-door advice with buses and trams, tracks and delays. **Not yet checked against the real API**: written from public examples, the parser is tolerant. |
| Live buses | [OVapi](http://v0.ovapi.nl) `GET /stopareacode` and `/stopareacode/{code}` | Community run, no key, non-commercial use: asked only for bus legs within 90 minutes. HTTP only, hence the exception for this one domain in `Info.plist`. Stop names are matched to NS's by name; no match means no live time. Failures are ignored. |
| Public transport without a key | Apple Maps `calculateETA` with `.transit` | A total time, without lines or delays. |
| Car | Apple Maps `MKDirections` with `departureDate` | Traffic is included. The trip at 03:00 tomorrow stands in for no traffic, asked once a day per route. *Now or later* asks +30 and +60 min, at most every 15 min. |
| Bike | Apple Maps walking route at 16 km/h | MapKit has no cycling directions. |
| Rain | [Buienradar](https://www.buienradar.nl) `gpsgadget.buienradar.nl/data/raintext`, then Open-Meteo `minutely_15` | Buienradar is the radar, for the Netherlands and Belgium; free for non-commercial use with a mention, which Settings → Departure has. Open-Meteo answers elsewhere or when it fails. |

## Planned: Notion, WHOOP

Plan: each is added under Settings → Integrations → *Add integration* that opens the service's own sign-in page (OAuth 2.0 with PKCE), so nobody has to paste tokens. The redirect comes back to wisp through a custom URL scheme; tokens are stored in the Keychain and refreshed automatically. Each service needs wisp registered once as an OAuth app (client ID only, no secret in the app where the service allows it).

| Service | Home tile | Data |
|---|---|---|
| WHOOP | *68% herstel* | latest recovery, strain, sleep |
| Notion | *2 bijgewerkt* | pages edited today |

## Agenda (EventKit)

Docs: <https://developer.apple.com/documentation/eventkit>

- Source: the macOS Calendar app, so every account in it counts (iCloud, Google, Exchange…). No key or sign-in of its own.
- Permission: *Agenda's* under Privacy & Security, asked from the Agenda tab or Settings → Calendar & weather (`NSCalendarsFullAccessUsageDescription`). Reading needs full access; wisp never writes.
- Read: today's events (title, start, end, all-day, calendar and its colour) from the calendars that are switched on in Settings. Nothing is stored or sent.
- The focus timer asks for the timed event that is on right now, to name the task.

## System info

- Battery: IOKit power sources. Storage: `URLResourceValues` of `/`. CPU: Mach host statistics and `proc_pid_rusage`. All local, nothing stored or sent.
- AirPods: `system_profiler SPBluetoothDataType -json` reports `device_batteryLevelLeft / Right / Case` for Apple headphones. Undocumented; if the keys change, the card says *Not connected*.
- Wi-Fi: `CWWiFiClient.shared().interface()?.ssid()` is nil without Location access. wisp asks only from Settings, with `NSLocationUsageDescription` explaining why.

## Shortcuts (Focus mode)

Docs: <https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac>

- macOS has no API for apps to turn a Focus mode on or off. *Do not disturb during focus* therefore runs two Shortcuts by name with `/usr/bin/shortcuts run`: **wisp Focus On** when a session starts and **wisp Focus Off** when it ends or is reset.
- The user makes them once in the Shortcuts app, each with the action *Set Focus* (*Do Not Disturb* on / off). If they don't exist, nothing happens.

## Weather (Open-Meteo)

Docs: <https://open-meteo.com/en/docs>, <https://open-meteo.com/en/docs/geocoding-api>

- Forecast: `GET https://api.open-meteo.com/v1/forecast` with `latitude`, `longitude`, `current=temperature_2m,weather_code,is_day`, `hourly=precipitation_probability,precipitation`, `daily=temperature_2m_max,temperature_2m_min`, `timezone=auto`, `timeformat=unixtime`, `forecast_days=2`.
- Places: `GET https://geocoding-api.open-meteo.com/v1/search?name=…&count=5&language=nl`, only when you search in Settings.
- Free for non-commercial use, no key, no account. Only the coordinates of the chosen place are sent; no location permission is needed. Default: Nijmegen.
- `weather_code` is a WMO code; wisp maps it to a Dutch description and an SF Symbol (`WeatherCode` in `Wisp/Agenda/Weather.swift`).

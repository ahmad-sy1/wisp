# Design

The boards in [`design/boards/`](../design/boards) are the visual source of truth. When this document and a board disagree, the board wins. All values below live in code in [`Wisp/Design/Theme.swift`](../Wisp/Design/Theme.swift); use the tokens, never a hard-coded colour or size.

| Board | Screen |
|---|---|
| [0](../design/boards/0-brand.png) | brand: name in the notch (the mark and icon are replaced by 0.1) |
| [0.1](../design/boards/0.1-brand-logo.png) | brand: logo and app icon, direction D |
| [0.2](../design/boards/0.2-design-system.png) | design system: every shared part with its states; the same sections larger in [`0.2-design-system-boards/`](../design/boards/0.2-design-system-boards) |
| [1](../design/boards/1-home.png) | Home |
| [2](../design/boards/2-mail.png) | Mail |
| [3](../design/boards/3-agenda-weather.png) | Agenda & weather |
| [3.1](../design/boards/3.1-agenda-now.png) | Agenda: the event that is on now |
| [4](../design/boards/4-focus-timer.png) | Focus timer |
| [5](../design/boards/5-clipboard.png) | Clipboard |
| [6](../design/boards/6-notes.png) | Notes |
| [7](../design/boards/7-system.png) | System |
| [8](../design/boards/8-notifications-collapsed.png) | mail notification, closed-notch states |
| [9](../design/boards/9-music.png) | Music (first version, replaced by 9.1–9.6) |
| [9.1](../design/boards/9.1-music-spectrum.png) | Music: live spectrum |
| [9.2](../design/boards/9.2-music-video.png) | Music: video in a browser |
| [9.3](../design/boards/9.3-music-paused.png) | Music: paused |
| [9.4](../design/boards/9.4-music-nothing-playing.png) | Music: nothing playing |
| [9.5](../design/boards/9.5-music-permission.png) | Music: one-time permission |
| [9.6](../design/boards/9.6-closed-notch-mini-spectrum.png) | closed notch: mini spectrum, video, paused |
| [9.7](../design/boards/9.7-closed-notch-focus-music.png) | closed notch: focus and music together (planned) |
| [10.1](../design/boards/10.1-settings-notch.png) | Settings: Notch (tabs on/off and order, Home tiles); being replaced by 10.1.1 |
| [10.1.1](../design/boards/10.1.1-notch-page-new-design.png) | Settings: Notch with integrations and *More* (rows keep their options) |
| [10.1.2](../design/boards/10.1.2-tabbar-full-more.png) | tab bar: the *More* menu (compacted so it stays inside the panel) |
| [10.1.3](../design/boards/10.1.3-choosing-home-tab.png) | Settings: choosing what Home shows (planned) |
| [10.2](../design/boards/10.2-settings-general.png) | Settings: General |
| [10.3](../design/boards/10.3-settings-integrations.png) | Settings: Integrations; being replaced by 10.3.4 |
| [10.3.1](../design/boards/10.3.1-integrations-modal.png) | *Add integration* window |
| [10.3.2](../design/boards/10.3.2-manage-integrations-single.png), [10.3.2.1](../design/boards/10.3.2.1-manage-modal.png) | Manage window, in the app and on its own |
| [10.3.3](../design/boards/10.3.3-manage-integrations.png) | Manage window: four services in four states |
| [10.3.4](../design/boards/10.3.4-integration-rows-status.png) | Settings: Integrations with status rows (planned) |
| [10.4](../design/boards/10.4-settings-calendar-weather.png) | Settings: Calendar & weather |
| [10.5](../design/boards/10.5-settings-music.png) | Settings: Music |
| [10.6](../design/boards/10.6-settings-focus.png) | Settings: Focus |
| [10.9](../design/boards/10.9-integration-page-template-whoop.png) | Settings: page template for an integration, with WHOOP (planned) |
| [10.10](../design/boards/10.10-sidemenu.png) | Settings: sidebar with few and many integrations (planned) |
| [11](../design/boards/11-compact-notch-states.png) | closed notch: departure and GitHub states |
| [11.1](../design/boards/11.1-open-notch-home-layouts.png) | Home with 4, 3, 2 and 1 places (planned) |
| [11.2](../design/boards/11.2-home-items-three-sizes.png) | Home items in three sizes (planned) |
| [11.3](../design/boards/11.3-integration-tab-template.png) | template for an integration's tab (planned) |
| [12](../design/boards/12-departure.png) | Departure |
| [13](../design/boards/13-github.png) | GitHub |
| [14](../design/boards/14-settings-departure.png) | Settings: Departure |
| [15](../design/boards/15-settings-github.png) | Settings: GitHub |

## App icon

The icons live in `Wisp/Resources/Assets.xcassets`. `AppIcon` uses the 1024 × 1024 tile of board 0.1 from 128 pt up; 16 and 32 pt are rendered from [`docs/media/app-icon-small.svg`](media/app-icon-small.svg), which drops the outer ring and thickens the ring and dot. `MenuBarIcon` is a one-colour SVG marked as a template, so macOS colours it. The mark and wordmark are in `docs/media/`, each with a version for light backgrounds.

## Principles

- **Professional, Apple-like, quiet.** Pure black panel, flat cards, line icons (SF Symbols).
- **No mascot, no emoji, no gradients.** No glass or blur on the panel or cards; small keys may be glass (see [Glass](#glass)).
- **The notch never grows big.** One fixed panel size; content scrolls inside its card rather than stretching the panel.
- The name is always written in lower case: **wisp**.

## Size and layout

| | Value |
|---|---|
| Panel width | 600 pt |
| Inset top (below the camera) | 40 pt |
| Inset sides and bottom | 14 pt |
| Tab bar height | 28 pt, then 10 pt gap |
| Content area | 150 pt high, fixed for every tab |
| Panel height | 242 pt |
| Bottom corner radius | 26 pt open; about a third of the notch height when closed |
| Top corners | square, flush with the screen edge |

## Colour

| Role | Token | Value |
|---|---|---|
| Panel | `panel` | `#000000` |
| Card | `card` | `#141416` |
| Card border | `cardBorder` | `#1F1F22` |
| Button / pill idle | `control` | `#1C1C1E` |
| Hover | `controlHover` | `#222225` |
| Active tab | `activeTab` | `#2A2A2D` |
| Switch off, chosen segment | `trackOff` | `#3A3A3E` |
| Settings sidebar | `sidebar` | `#0B0B0D` |
| Modal | `modal` | `#0E0E10` |
| Row under the mouse | `rowHover` | `#18181B` |
| Border of fields, modals, chips | `lineStrong` | `#2A2A2D` |
| Text | `textPrimary` | `#FFFFFF` |
| Field labels, chip text | `textLabel` | `#D4D4D8` |
| Secondary text | `textSecondary` | `#A1A1AA` |
| Meta, section labels, placeholders | `textFaint` | `#71717A` |
| Disabled text | `textDisabled` | `#52525B` |
| Badge, dots | `badge` | `#FF453A` |
| Red text | `redText` | `#FF6961` |
| OK, music | `ok` | `#30D158` |
| Warning, shifts | `warning` | `#FF9F0A` |
| Review requests | `info` | `#0A84FF`, whatever the accent |
| Rain | `rain` | `#64D2FF` |
| NS badge | `nsYellow` | `#FFC917` |
| Accent (Settings) | `Accent` | `#0A84FF` (default), `#30D158`, `#FF9F0A`, `#BF5AF2`; each with a `hover` and a `pressed` shade |

## Shapes and type

- Radii: `smallCorner` 6 pt (a segment), `buttonCorner` 8 pt (buttons, fields, tabs, sidebar rows), `iconCorner` 11 pt, `cardCorner` 14 pt (cards and groups), `modalCorner` 16 pt, `panelCorner` 26 pt.
- Cards have a 1 pt border. Buttons are 28 pt high.
- Tab buttons: 32 × 28 pt, radius 8. Active: `activeTab` background and a white icon; idle: grey icon, no background.
- Badges: red capsule with the count, top right of the tab icon.
- Font: SF Pro (the system font). Titles 13–15 pt semibold, labels 11–12 pt, small meta 10–11 pt. Small labels above a title (*NU BEZIG*) are 10.5 pt medium with slight tracking.

## Tab bar

Left, in this order: **Home · Mail · Agenda · Vertrek · GitHub · Focus · Muziek · Klembord · Notities · Systeem · Bestanden**. Right: **Settings** (sliders icon). A tab may put its own controls just left of Settings, as Mail does with *Alles / Ongelezen / ↗*, Agenda with today's date and Music with the output device.

Opened with the shortcut (⌥Space, Settings → General, board 10.2) the panel stays until the shortcut again, Esc or a click elsewhere; ← and → walk through the visible tabs when no text field has the keyboard.

## Home tab

Settings → Notch (board 10.1) has a chip per tile: *Nu bezig*, GitHub, WHOOP, Muziek, Notion. The board switches Notion off to show the *+* chip; by default all five are on. At least one stays on. What is left fills the room, in the fixed 150 pt area: with *Nu bezig* on, one tile fills the column, two go below each other, three are two above one; with it off the tiles take the full width, and *Nu bezig* alone does too.

## Agenda tab

Three cards in the fixed 150 pt area (boards 3 and 3.1):

| Part | Spec |
|---|---|
| Left card (348 pt) | today's events in 28 pt rows: time (13 pt, grey), a 3 × 16 pt bar, title (13 pt semibold). Done: grey bar, struck-through grey title. A red (`badge`) *nu* line with the time between done and coming. The next event shows *over 2u 55m* in its bar colour. Scrolls when the day is full, starting at the *nu* line |
| Event on now (board 3.1) | a raised card just above the *nu* line (`control` fill, `cardBorder` hairline, radius 14, 15 pt from the card edges): a *NU* label (11 pt bold white on the accent colour, radius 6), the title (15 pt semibold), the times (13 pt grey), *nog 2u 22m* on the right (13 pt medium), and below a 5 pt bar (accent on `activeTab`) that fills up as the event runs. Shifts use `warning` instead of the accent. A long title pushes the times out rather than being cut off |
| Order | all-day, done (struck through), on now (card), *nu* line, coming |
| Bar colour | shifts `warning`, everything else its calendar's colour |
| Weather card (70 pt) | SF Symbol 28 pt light, temperature 22 pt semibold, *Nijmegen · half bewolkt* |
| Departure card (70 pt) | *Vertrek voor je dienst*, *16:25 · 22 min reizen* (15 pt semibold), *Droog tot 22:00* |
| Tab bar | *Vandaag · donderdag 29 oktober* just left of Settings |

States the board doesn't show, built in the style of the other tabs and open to a design:

- No Calendar access yet / refused: the calendar icon, a short line and *Toegang geven* or *Open Systeeminstellingen*, like Mail's empty states.
- Nothing left today: below the *nu* line a header *Morgen · vrijdag 30 oktober* (12 pt semibold, grey, with a thin grey rule) and tomorrow's first two timed events (or its all-day events when nothing is timed), in the normal row style without a countdown.
- Nothing today or tomorrow: *Niets gepland vandaag.*
- No shift left today: the departure card reads *Geen diensten meer vandaag* (as on board 3.1), the rain line, and today's low and high.
- Leaving time passed but the shift hasn't started: *Nu · 22 min reizen*.
- All-day events sit at the top as *hele dag*.

## Focus tab

Two cards in the fixed 150 pt area (board 4):

| Part | Spec |
|---|---|
| Left card (315 pt) | a 108 pt ring (7 pt, accent colour) that empties clockwise; the time left (26 pt bold) and the state (*gereed*, *focus*, *gepauzeerd*, *klaar*, 12 pt grey) inside. Next to it the task (15 pt semibold) with a pencil, *Start* / *Pauze* (accent) and *Reset*, and the source with a dot: green for *Automatisch · IntelliJ IDEA · wisp* and *Uit agenda*, grey for *Zelf gekozen* |
| Right card | *Duur* (12 pt grey), a segmented control *25 / 50 / 90 min* across the card (board 0.2 replaces the separate pills of board 4), two checkboxes |
| Tab bar | *Vandaag 3 sessies · 1u 45m* just left of Settings |
| Closed notch | while a session runs or is paused: a small ring left of the camera, the time left (10.5 pt semibold) right of it. It replaces the music wings; paused shows both in grey |

States the board doesn't show, built in the same style:

- Before a session: a full ring, the chosen duration and *gereed*. The durations can't change while a session runs.
- Done: an empty ring, *00:00* and *klaar*; the notch opens on the Focus tab and plays the *Glass* sound if sounds are on.
- Editing the task: the title becomes a text field; Return saves, Escape cancels.

Settings → Focus (board 10.6): each rule shows *Geleerd* or *Zelf ingesteld*. *+ Koppeling toevoegen* opens a form inside the card, which the board doesn't show: an app menu (the running apps and *Andere…*), an optional project, the task, *Annuleren* and *Toevoegen*. Not built yet: the board's *Standaard* rules and sites (*Safari · trello.com*).

## Clipboard tab

One scrolling card in the fixed 150 pt area (board 5):

| Part | Spec |
|---|---|
| Row (46 pt) | a 28 pt grey tile with *URL*, *</>* or *Aa* (bold, grey); the text on one line (13 pt, code 12 pt monospaced, line breaks as ⏎); how long ago (11 pt grey: *nu*, *2 min*, *1 u*, *3 d*); a *Kopieer* key that reads *Gekopieerd* in the accent colour for a moment |
| Tab bar | a 190 pt search field *Zoek in klembord* just left of Settings |

States the board doesn't show: nothing copied yet (*Kopieer iets en het verschijnt hier.*), nothing found for a search, and the history switched off in Settings, each as the clipboard icon with a short grey line.

## Notes tab

Two cards in the fixed 150 pt area (board 6):

| Part | Spec |
|---|---|
| Left card (241 pt) | the notes, newest first: the first line (14 pt) and when (12 pt grey: *13:50*, *gisteren*, *28 okt*). A click puts a note in the editor (its row turns `activeTab`); right-click offers *Kopieer* and *Verwijderen* |
| Right card | a text field with *Typ een notitie…*; at the bottom *Alleen op deze Mac* and *Opslaan* (accent; ⌘↩) |
| Tab bar | *3 notities* just left of Settings |

Differences from the board: the bottom line reads *Alleen op deze Mac* instead of *Synct naar Notion* until the Notion integration exists. While a note is being edited it reads *Notitie bewerken* with a cross to stop. No notes yet: the pencil icon and *Je notities verschijnen hier.*

## System tab

Four equal cards in the fixed 150 pt area (board 7), each with a label (12 pt grey), a big value (24 pt bold) and a line at the bottom (12 pt grey):

| Card | Spec |
|---|---|
| Batterij | percentage, a 6 pt bar (`ok`, `badge` at 20 % or less on battery), *nog 6u 10m*, *Vol over 1u*, *Aan de lader* or *Geen batterij* |
| AirPods | the model name; *Links / Rechts / Case* with percentages, below 20 % in `warning`. Not connected: the AirPods icon and *Niet gekoppeld* |
| CPU | percentage, a line through the last 40 seconds (accent), *IntelliJ IDEA gebruikt 11%* (may wrap to two lines) |
| Opslag | free space in whole GB, a bar for what is used (accent), *vrij van 512 GB* |
| Tab bar | the Wi-Fi icon and network name; *Wi‑Fi* without Location access, *Wifi uit* when off |

## Departure tab

Two cards in the fixed 150 pt area (board 12):

| Part | Spec |
|---|---|
| Left card (332 pt) | *NAAR HUIS* or *NAAR {AFSPRAAK}* (10.5 pt) with a switch for public transport, car and bike; *Vertrek over* with the minutes (34 pt bold, white, `warning` when tight, `badge` when late); right *Thuis 16:21* (13 pt semibold) and the status (`ok` *Op tijd*, otherwise the delay or jam in `warning` or `badge`) |
| Route | chips (22 pt, `control`) split by chevrons, at most three plus *+1*: a grey *loop*, a yellow `nsYellow` *NS* with the track, a white badge with the line number with time and stop |
| Right card, public transport | *ALTERNATIEVEN*: up to three rows of time, *Trein → Bus 300*, *op tijd* / *+4 min* / *uitval*. A cancelled time is grey |
| Right card, car | *NU OF STRAKS*: now, +30 and +60 with their minutes, and the advice (*Wacht 60 min, scheelt 15 min* in `warning`, *Ga nu, wachten helpt niet* in `ok`). The board doesn't draw this card; built in the same style |
| Right card, bike | *BUIEN*: *Regen over 10 min* and *Ga nu of wacht 25 min*, or *Droog onderweg*. Also built without a board |

Not on the board: *Geen reis in zicht*, the prompt for a home address, the prompt for calendar access, and without an NS key the card says so instead of listing alternatives. Closed notch (board 11): the mode icon and minutes left of the camera, right of it *15:42 spoor 3*, *+15 file A15* or *regen 10 min* (`rain`). A trip goes before a GitHub status.

## GitHub tab

Two cards in the fixed 150 pt area (board 13):

| Part | Spec |
|---|---|
| Left card (306 pt) | a switch *Mijn PR's · 4 / Reviews · 2* (22 pt pills on `control`); rows of 25 pt: an indicator, the title (12.5 pt), *wisp #43* (11 pt grey), the status (11 pt medium). Scrolls inside the card. A click opens the pull request |
| Indicator and status | spinner and *2/5*; red *gefaald*; green *klaar*; orange *3 reacties* until you've seen them |
| Right card | *CONTRIBUTIONS*, *16 weken*; a grid of 16 × 7 in green levels; *dagen streak*, *commits/week* and *gemerged* (15 pt bold above 10.5 pt grey) |
| Tab | the pull request glyph (`WispGlyph`, SF Symbols has no match) with a blue `info` count of requested reviews |

Not on the board, in the same style: a failed row gets a second line with the failed job and ↗, which opens that run. Reviews have a blue dot and no check status. *Geen open pull requests*, *Niets te reviewen*, and a *Koppel GitHub* state like Mail's.

## Closed notch and mail peek

A status only shows while its tab is switched on in Settings → Notch.

On the closed notch the wings show one thing at a time, in this order: a running focus session (ring and time), an urgent status (a trip, CI failed, review requested, new comments; board 11), music (artwork and mini spectrum, boards 9.6), a calm status (a CI run going), unread mail (an envelope and the red count, board 8). Unread mail can be switched off in Settings → Gmail.

A status (`StatusWings`, board 11) has an icon and short text left of the camera and short text right of it, 12 pt semibold. Both wings are as wide as the wider one, because the window is centred on the camera. So every status is a word or a number, shorter than board 11, and the tab has the details: *CI* and *3/4* for a run, *CI* and *#47* in red for a failure, the icon with a blue dot and *Review* (or the count in blue and *Reviews*), the pull request and a comment count, and for a trip the countdown with one time or delay. A wing is at most 96 pt, and digits are measured and drawn at equal width, so a countdown or *3/4* doesn't move the notch unless it gains a digit. The notch drops 2 pt and springs back on a new event (*Tik-animatie*); CI gets a short flash of red or green. A click opens the tab it comes from. Everything stays quiet during a focus session with *Niet storen* and under a permission request.

New mail peeks out of the notch (board 8): 420 × 132 pt, corner radius 26.

| Part | Spec |
|---|---|
| Top | a 38 pt avatar, the sender (15 pt semibold), *nu* on the right (12 pt grey), the subject below (13 pt) |
| Keys | three equal 30 pt keys: *Openen* (white, black text), *Verwijderen* and *Later* (`control`) |
| Timing | closes after 6 s, or after the close delay once the mouse has been on it |

The peek shows the subject only, not the first line of the message: wisp fetches headers, not bodies. It stays away while the panel is open, while a permission request waits, and during a focus session with *Niet storen*.

## Music tab

Two cards in the fixed 150 pt area (boards 9.1–9.6):

| Part | Spec |
|---|---|
| Left card (331 pt) | artwork 120 pt (radius 14); source app in small caps; title 15 pt semibold; artist · album; progress with elapsed and remaining time; glass previous / play-pause / next |
| Right card | *SPECTRUM* label, output quality on the right ("48 kHz · 32-bit"); 24 green bars (`ok`) from bass to treble; "Bas · Mid · Hoog" shares and the loudness in dB; volume slider at the bottom |
| Tab bar | the output device ("AirPods Pro") just left of Settings; it appears nowhere else |
| Closed notch | artwork left of the camera, an 8-band mini spectrum right of it |

| State | Board | What changes |
|---|---|---|
| Playing | 9.1 | bars move with the sound |
| Video in a browser | 9.2 | same, the video thumbnail as artwork, or a dark red tile with a play icon |
| Paused | 9.3 | flat grey dashes and *Gepauzeerd*; closed notch: grey dots, gone after a minute |
| Nothing playing | 9.4 | empty artwork, *Er speelt niets*, a white *Open Spotify* button; right card waits (*Wacht op geluid*) |
| Before permission | 9.5 | the right card asks *Laat wisp meeluisteren?* with *Toestaan* and *Niet nu* |

Deliberate differences from the boards:

- The source label is the app's name (*SPOTIFY*, *BRAVE BROWSER*). macOS reports the app, not the website, so it can't say *YOUTUBE · SAFARI*.
- The loudness reads "−10 dB" without the word *Luid*, so the line fits the card on one row; the word shows as a tooltip.
- The playback keys are glass (see [Glass](#glass)), not the solid white key of the boards.

## Settings window

A 760 × 620 pt window with the title bar drawn over it (boards 10.1–10.6), always dark:

| Part | Spec |
|---|---|
| Sidebar | 205 pt, `sidebar` fill, a 1 pt `cardBorder` line on its right. The wisp dot and name (16 pt semibold) below the window buttons, then the pages: SF Symbol + 13 pt label in 30 pt rows; the active page on `activeTab`, radius 8 |
| Page | black, 31 pt side margin. Title 26 pt bold, optional subtitle 13 pt grey, an action top right (*Add integration*: accent fill, white semibold) |
| Group | a 12 pt grey header, then a card: `card` fill, `cardBorder` 1 pt, radius 14; rows at least 46 pt, split by 1 pt `cardBorder` lines, 15 pt inside |
| Row | title 13 pt, optional 11.5 pt grey line below; on the right a switch, a pop-up, or a secondary button |
| Note | 11.5 pt grey text under the last group |

Built in the same style, not on the boards (open to a design):

- **Notch**: a tab's options open below its row (indented under the title, small switches) when you click the row. Rows move out of the way while you drag one (whole row is the handle); a switched-off tab's icon and title are dimmed. The Home tiles of board 10.1 come once GitHub, Notion and WHOOP exist.
- **Integrations**: *Add integration* opens its own window (below). *Manage* opens the Manage window (below); Gmail's ✕ asks before it disconnects. Music has *Manage* (opens the Music page) but no ✕. The dot is the service's colour; errors show in the grey line.
- **Calendar & weather**: without access, one row with *Give access* or *Open System Settings*. *Change* opens a search sheet.
- **Music**: macOS doesn't tell apps whether system audio is allowed, so the dot shows wisp's own switch (*On* / *Off*).
- **Focus**: with no learned rules, one row *No rules yet*.
- **General**: after a language change, the grey line says to restart and a *Restart* button appears next to the pop-up.

Settings → Departure (board 14) follows the board, plus *Reistijd naar je dienst*, moved here from Calendar & weather, and a row for calendar access when it is missing. The bike-or-car choice moved too: there is one *Standaard vervoer*. *On foot* is gone from it, as on the board. An NS key is added under Integrations, like Gmail's password.

Settings → GitHub (board 15) follows the board. Not connected, the account row offers *Gebruik GitHub CLI-login* (if `gh` is installed) and *Token toevoegen…*; *Alle (6)* opens a sheet with a checkbox per repository.

Settings → Music (board 10.5): the system-audio row reads *Aan* / *Uit*, not *Toegestaan*, because macOS doesn't tell apps whether it granted access. *Mini spectrum* and *Battery saver* are dimmed while the live spectrum is off.

## Add integration (board 10.3.1)

A 680 × 556 pt window over all of Settings, which dims to 60 % black. Search (⌘K), filter chips, the list on the left, the chosen service on the right, and ↑↓, ↩ and esc from the keyboard.

- It lists only services that work, so the counts are lower than on the board and a category without a service has no chip. Music works automatically and isn't listed.
- *Add …* and *Manage* open the Manage window; GitHub still has its own page.
- *Request an integration* opens a new GitHub issue in the browser.

## Manage window (boards 10.3.2, 10.3.3)

One 460 × 500 pt window for every service: icon, name and status, the fields, a help link, a privacy line, the buttons. Only the fields come from the service (`ManageSpec`).

| State | Status | Buttons |
|---|---|---|
| Empty | *Not connected* | Cancel, Connect (grey until the fields are complete) |
| Checking | *Checking*, fields locked | Cancel, *Checking…* |
| Failed | *Couldn't connect*, a red field and what to do | Cancel, Try again |
| Connected | *Connected*, the secret only as dots | Disconnect on the left, Done on the right |

- A key is checked with the service first and only stored when it works.
- To change a key, disconnect and fill it in again; the board has no edit state.
- The board's *checked 2 min ago* isn't shown yet: wisp keeps no time of the last check.

## Buttons

All in `Wisp/Design/Buttons.swift`, 28 pt high, radius 8 (board 0.2):

| Style | For | Fill |
|---|---|---|
| `AccentButtonStyle` | the one next step in a view | accent, white semibold text |
| `SecondaryButtonStyle` (`.settings` in Settings) | every other action | `controlHover`; `activeTab` on hover, `control` when pressed |
| `DangerButtonStyle` (`.danger`) | *Disconnect* | none, `redText`; a faint red behind it on hover and press |

Disabled, the fill drops to `control` (none for danger) and the text to `textDisabled`.

`IconButtonStyle` is the 28 × 28 pt icon-only button. `ServiceIcon`, `FilterChip`, `SearchField`, `FormField`, `StatusPill` and `ModalBackdrop` are in `Wisp/Design/` too. Buttons in a modal are 32 pt high.

`SegmentedControl` (`Wisp/Design/SegmentedControl.swift`) holds two to four fixed choices: a `control` track with radius 8, the chosen segment on `trackOff` with radius 6. Segments show words or, with a tooltip, icons. Disabled, the text drops to `textDisabled` and the chosen segment to `activeTab`.

## Glass

Small controls may use glass: Liquid Glass (`glassEffect`) on macOS 26, a frosted material with a thin light edge on older systems (`Wisp/Design/Glass.swift`). Glass is for keys only; the panel and the cards stay flat and black.

## Tab bar with More (boards 10.1.1, 10.1.2)

Up to 8 tabs fit. With more, the last spot becomes *… 4 ⌄* and holds the rest, in tab order; the arrow keys still walk through every tab. Its menu is 26 pt rows inside the panel, four at most before it scrolls, without the board's *More tabs* title, so the panel never grows.

Settings → Notch shows Home apart as the fixed first tab, and marks the rows that end up in *More*. A row still opens for its options, which board 10.1.1 leaves out. An integration's tab shows its letters.

## Language

The interface is English, with Dutch as the first translation; wisp follows the Mac's language unless one is picked in Settings ([#12](https://github.com/ahmad-sy1/wisp/issues/12)). The boards and the texts quoted in this document are the Dutch version; the English text is in `Wisp/Resources/Localizable.xcstrings`. Keep interface text short (Dutch runs about a third longer than English, so check that it fits) and don't build text into images. Code, comments, commit messages and these documents are in English.

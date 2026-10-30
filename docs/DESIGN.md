# Design

The boards in [`design/boards/`](../design/boards) are the visual source of truth. When this document and a board disagree, the board wins. All values below live in code in [`Wisp/Design/Theme.swift`](../Wisp/Design/Theme.swift); use the tokens, never a hard-coded colour or size.

| Board | Screen |
|---|---|
| [0](../design/boards/0-brand.png) | brand: mark, app icon, name in the notch |
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
| Text | `textPrimary` | `#FFFFFF` |
| Secondary text | `textSecondary` | `#A1A1AA` |
| Badge | `badge` | `#FF453A` |
| OK, music | `ok` | `#30D158` |
| Warning, shifts | `warning` | `#FF9F0A` |
| Accent (Settings) | `Accent` | `#0A84FF` (default), `#30D158`, `#FF9F0A`, `#BF5AF2` |

## Shapes and type

- Cards: radius 16 pt with a 1 pt border. Buttons: radius 9 pt, 28 pt high.
- Tab buttons: 32 × 28 pt, radius 9. Active: `activeTab` background and a white icon; idle: grey icon, no background.
- Badges: red capsule with the count, top right of the tab icon.
- Font: SF Pro (the system font). Titles 13–15 pt semibold, labels 11–12 pt, small meta 10–11 pt. Small labels above a title (*NU BEZIG*) are 10.5 pt medium with slight tracking.

## Tab bar

Left, in this order: **Home · Mail · Agenda · Focus · Muziek · Klembord · Notities · Systeem · Bestanden**. Right: **Settings** (sliders icon). A tab may put its own controls just left of Settings, as Mail does with *Alles / Ongelezen / ↗*, Agenda with today's date and Music with the output device.

## Agenda tab

Three cards in the fixed 150 pt area (boards 3 and 3.1):

| Part | Spec |
|---|---|
| Left card (348 pt) | today's events in 28 pt rows: time (13 pt, grey), a 3 × 16 pt bar, title (13 pt semibold). Done: grey bar, struck-through grey title. A red (`badge`) *nu* line with the time between done and coming. The next event shows *over 2u 55m* in its bar colour. Scrolls when the day is full, starting at the *nu* line |
| Event on now (board 3.1) | a raised card just above the *nu* line (`control` fill, `cardBorder` hairline, radius 12, 15 pt from the card edges): a *NU* label (11 pt bold white on the accent colour, radius 6), the title (15 pt semibold), the times (13 pt grey), *nog 2u 22m* on the right (13 pt medium), and below a 5 pt bar (accent on `activeTab`) that fills up as the event runs. Shifts use `warning` instead of the accent. A long title pushes the times out rather than being cut off |
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

## Glass

Small controls may use glass: Liquid Glass (`glassEffect`) on macOS 26, a frosted material with a thin light edge on older systems (`Wisp/Design/Glass.swift`). Glass is for keys only; the panel and the cards stay flat and black.

## Language

The interface is English, with Dutch as the first translation; wisp follows the Mac's language unless one is picked in Settings ([#12](https://github.com/ahmad-sy1/wisp/issues/12)). The boards and the texts quoted in this document are the Dutch version; the English text is in `Wisp/Resources/Localizable.xcstrings`. Keep interface text short (Dutch runs about a third longer than English, so check that it fits) and don't build text into images. Code, comments, commit messages and these documents are in English.

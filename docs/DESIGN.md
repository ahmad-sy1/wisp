# Design

The boards in [`design/boards/`](../design/boards) are the visual source of truth. When this document and a board disagree, the board wins. All values below live in code in [`Wisp/Design/Theme.swift`](../Wisp/Design/Theme.swift); use the tokens, never a hard-coded colour or size.

| Board | Screen |
|---|---|
| [0](../design/boards/0-brand.png) | brand: mark, app icon, name in the notch |
| [1](../design/boards/1-home.png) | Home |
| [2](../design/boards/2-mail.png) | Mail |
| [3](../design/boards/3-agenda-weather.png) | Agenda & weather |
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

Left, in this order: **Home · Mail · Agenda · Focus · Muziek · Klembord · Notities · Systeem · Bestanden**. Right: **Settings** (sliders icon). A tab may put its own controls just left of Settings, as Mail does with *Alles / Ongelezen / ↗* and Music with the output device.

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

The interface is in Dutch today. The plan is English as the base language with Dutch as the first translation, so wisp works for everyone ([#12](https://github.com/ahmad-sy1/wisp/issues/12), [ROADMAP.md](ROADMAP.md)). Until then, keep new interface text short and easy to translate, and don't build text into images. Code, comments, commit messages and these documents are in English.

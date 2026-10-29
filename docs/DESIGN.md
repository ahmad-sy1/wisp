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
| [9](../design/boards/9-music.png) | Music |

## Principles

- **Professional, Apple-like, quiet.** Pure black panel, flat cards, line icons (SF Symbols).
- **No mascot, no emoji, no gradients, no glass or blur.**
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

## Language

The interface is in Dutch. Code, comments, commit messages and these documents are in English.

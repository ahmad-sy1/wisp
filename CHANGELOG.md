# Changelog

## Unreleased

- Settings is a window with a sidebar: General, Notch (each tab's options), Integrations, Calendar & weather, Music and Focus (boards 10.1–10.6, #28); the departure card says how you travel (*22 min fietsen*)
- New mail peeks out of the notch with *Open / Delete / Later* (Delete moves it to the Gmail trash), and the closed notch shows the unread count; both can be switched off (board 8)
- System tab: battery, AirPods, CPU with the busiest app, storage, and the Wi-Fi name (with Location access from Settings) (board 7)
- Notes tab: quick notes stored on this Mac, click to edit, right-click to copy or delete (board 6)
- Disabled buttons are dimmed
- Clipboard tab: the last 20 copied texts with search and *Copy*, stored only on this Mac, never passwords; can be switched off in Settings (board 5)
- Focus timer tab: 25 / 50 / 90 minutes, a ring that keeps counting in the closed notch, the task from the calendar or the app in front (learns from corrections), today's sessions, *Do not disturb* through Shortcuts and *Start music* (board 4)
- English interface with Dutch as the first translation (String Catalogs), a language choice in Settings, and a CI check for missing translations (#12)
- Debug builds: `-settingsPage <page>` opens Settings on a page, and with `-snapshot` draws that window
- Debug builds: `-snapshot <file.png>` draws the open panel to a PNG, also with the screen locked
- Agenda: once nothing is left today, the timeline shows tomorrow's first two events under *Morgen*
- Agenda: the event that is on now gets its own card with *NU*, the time left and a progress bar (board 3.1)
- Debug builds: `-agendaTime 21:30` shows the Agenda tab at another time of today
- Agenda & weather tab: today's timeline from the macOS Calendar app with a *nu* line and a countdown, the weather from Open-Meteo, and when to leave for your next shift (board 3); Settings → Agenda & weer for calendars, shifts, the ride and the place
- Music: a live spectrum of what plays (24 bands, bass/mid/treble mix, loudness), the output quality, a one-time permission card, and states for paused and nothing playing; a real mini spectrum on the closed notch, which stays greyed for a minute after a pause (boards 9.1–9.6)
- The playing app above the song title, and *Open Spotify* when nothing plays
- Settings → Muziek: a switch for the live spectrum
- Glass music controls with hover and press feedback (#9)
- The hooks installer only touches wisp's own entries (#10)
- Music tab: artwork, progress, controls, output device and volume; artwork and an equalizer on the closed notch while music plays; the music tile on Home (#7)
- Local builds are signed with a Developer ID, so macOS remembers Keychain access across updates (#7)
- Mail tab with Gmail: read-only inbox over IMAP with push, *Alles / Ongelezen*, open in Gmail, unread badge (#6)
- Opening wisp again (Spotlight, Finder) opens Settings (#5)
- Sessions in an IDE that was started from the Claude desktop app now show up (#5)
- Claude Code: live sessions on Home, approvals from the notch, hooks installer with backup and confirmation (#4)
- Build check on every pull request; `install.sh` and a signed, notarized `release.sh` (#3)
- The notch panel: 600 pt, tab bar, fixed content area, Settings window with accent colour, close delay and open at login (#2)

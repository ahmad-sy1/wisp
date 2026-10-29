# Overdracht: Coucou-aanpassingen (okt 2026)

Fork van [Louis-CFM/coucou](https://github.com/Louis-CFM/coucou), een macOS-app die in de notch woont (Mochi).
Lees eerst `CLAUDE.md` (regels van het project) en daarna dit bestand.

## Bouwen en installeren
```bash
cd ~/coucou/NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath build build
pkill -f "/Applications/Coucou.app/Contents/MacOS/Coucou"; rm -rf /Applications/Coucou.app
ditto build/Build/Products/Debug/Coucou.app /Applications/Coucou.app && open /Applications/Coucou.app
```
- Draai `xcodegen` opnieuw na het toevoegen van een nieuw `.swift`-bestand, anders vindt de build het niet.
- Debug-build met ad-hoc-ondertekening (geen Apple Developer-account nodig). Xcode 27 staat op `/Applications/Xcode.app`.
- Logs: `~/Library/Logs/NotchBuddy/nb.log` (hook-events), `spotify.log`.

## Wat er gebouwd is (nog niet gecommit, alles op `main`)

### 1. WHOOP-integratie — `Sources/App/WhoopService.swift`
- OAuth 2.0 via de officiële WHOOP API v2. Redirect `coucou://whoop/callback`; het URL-schema staat in `project.yml` en wordt afgehandeld in `AppDelegate.application(_:open:)`.
- Haalt elke 15 minuten de laatste recovery, cycle (strain) en sleep op (naps worden overgeslagen). Refresh-tokens wisselen bij elke vernieuwing en worden opgeslagen in de Keychain (`whoop-*` keys).
- Notch-kaart `WhoopCardView` (in `IslandViewContent.swift`): Recovery % in de kleuren van WHOOP, plus strain, slaap en HRV/rustpols.
- Settings: velden voor Client ID en Secret, de redirect URI, en knoppen Connect en Disconnect.
- De chat in de notch (`ClaudeService.systemPromptWithContext`) krijgt de WHOOP-cijfers als context mee.
- **Status: werkt** (5 okt 2026): de cijfers komen binnen, zie `whoop.log`. De kaart volgt design 3a uit Claude Design: drie rijen (Strain, Sleep, HRV · RHR) en onderaan een recovery-balk in de kleuren van WHOOP.

### 2. Muziek / Now Playing — `Sources/App/NowPlayingService.swift` + `Helpers/NowPlayingBridge.m`
- Vervangt de oude SpotifyService. Leest wat macOS als "Now Playing" toont (YouTube in Brave, Spotify, Music…).
- MediaRemote weigert apps van derden sinds macOS 15.4, daarom laadt `/usr/bin/perl` (Apple-ondertekend) onze eigen dylib. Die stuurt JSON-regels via stdout en krijgt commando's (`toggle`/`next`/`previous`) via stdin. Gebaseerd op events, zonder polling. De dylib wordt gebouwd in een build-fase in `project.yml` (`postCompileScripts`).
- Dichte notch (`.hidden`) terwijl er muziek speelt: aan elke kant een vleugeltje met links de albumhoes en rechts een equalizer (`MusicWingsView` in `IslandRootView.swift`). Gaat 2 s na pauze weg.
- De pill `integration_spotify` heet nu "Music" en toont `NowPlayingCardView`. Logs: `nowplaying.log`.
- Design uit Claude Design (project "Notch Music", `Notch Music.dc.html`) ingebouwd: 2a (vleugeltjes: hoes 20 pt, balkjes 2,5×14, die bij pauze tot stipjes inzakken), 2b (Claude bezig → mini-Mochi in statuskleur rechts) en 1b (muziekkaart met Mochi in hoeskleur, equalizer in de kopregel, hoes 34 pt, voortgangsbalk en knoppen). WHOOP volgt 3a ook. Nog niet gedaan: 3a voor GitHub en de Claude-kaart.

### 2b. (oud) Spotify-integratie: verwijderd, stond hieronder ter referentie
- Gebruikt de lokale Spotify-app, zonder account of sleutel. Nummerwissels komen binnen via `DistributedNotificationCenter` (`com.spotify.client.PlaybackStateChanged`), dus er wordt niet gepolld. Albumhoes en bediening gaan via AppleScript.
- Start Spotify nooit zelf (controleert eerst `isRunning`).
- Kaart `SpotifyCardView`: albumhoes, titel, artiest en de knoppen vorige, play/pause en volgende.
- Vereist eenmalige macOS-toestemming via Automatisering (Coucou → Spotify). **Nog niet getest met echte muziek.**

### 2c. Gmail-inbox — `Sources/App/GmailService.swift` + `Sources/App/InboxView.swift`
- IMAP (imap.gmail.com:993) met een Google-app-wachtwoord; geen Google Cloud-project nodig. Een minimale IMAP-client op `NWConnection` (LOGIN, EXAMINE, SEARCH, FETCH, IDLE), zonder dependencies.
- Alleen lezen: EXAMINE + BODY.PEEK, dus Coucou markeert niets als gelezen. Nieuwe mail komt via IDLE (push), elke 25 min ververst en opnieuw verbonden na sleep/wake.
- De chat-tab in de header is vervangen door een envelop-tab (`.inbox`) met een badge voor het aantal ongelezen mails. De chat zelf bestaat nog (window-drop opent hem).
- Nieuwe ongelezen mail: geluid `pop` en een banner onder de dichte notch (afzender + onderwerp, 6 s; blijft staan zolang je erop hovert). Klikken opent de inbox. Een rij aanklikken opent de thread in Gmail.
- Settings → Gmail: adres + app-wachtwoord (Keychain: `gmail-address`, `gmail-app-password`). Logs: `gmail.log`.
- **Nog niet getest met een echt account** (alleen de TLS-verbinding, een geweigerde login en het ontcijferen van headers).

### 3. VS Code → IntelliJ
- De vaste pill (`integration_claude`) heet nu "IntelliJ". `IDELauncher` (in `IslandViewContent.swift`) opent IntelliJ, Ultimate of Community, op de projectmap van de sessie.
- `HookServer.isIDESession` accepteert JetBrains-sessies (`__CFBundleIdentifier` begint met `com.jetbrains.`) **en** VS Code. Sessies uit de Claude-desktopapp worden bewust genegeerd.
- De knop "Open terminal" na een afgeronde taak heet nu "Open IntelliJ".
- **Als IntelliJ vooraan staat** (`HookServer.ideIsFrontmost`): de notch klapt niet uit en toestemmingsvragen gaan direct terug als `ask`, zodat de prompt in de terminal van IntelliJ verschijnt.

### 4. Hover-gedrag van de notch
- Hover: alleen de notch zelf "popt" iets groter (+18×7 pt, veer). Er komt geen peek met Mochi meer bij hover (`IslandStateMachine.mouseEntered` in `.hidden`).
- Klikken opent de notch. Wegbewegen klapt hem na ±0,12 s dicht (`hoverOutDelay`).
- `keepOpen` in de state machine houdt hem open bij een goedkeuring, de chat, e-mail, het slepen van een bestand en de begroeting.
- Hover-status: `AppState.islandHovered`. De animatie zit in `IslandRootView` (`restingSize`, `hoverInSpring`/`hoverOutSpring`).
- De gebruiker heeft hier veel op bijgestuurd. Houd het subtiel: geen heen-en-weer-animaties.

## Configuratie bij de gebruiker
- Claude Code-hooks zijn geïnstalleerd (`~/.claude/settings.json` → `nb-hook`).
- Actieve integraties (maximaal 4): WHOOP, Spotify, GitHub, Notion.
- Gebruikt twee schermen (MacBook en LG UltraWide). De notch staat op het MacBook-scherm.
- De gebruiker is bezig met het instellen van een GitHub fine-grained token (alleen-lezen is genoeg).

## Open punten / ideeën
- Optioneel: WHOOP koppelen aan Claude Code of de Claude-app (MCP-server).
- Optioneel: sessies uit de Claude-desktopapp ook tonen.
- De wijzigingen committen (eventueel op een eigen branch). De bundle-ID `fr.louisraille.NotchBuddy` niet wijzigen.
- De systeemprompt in `ClaudeService` noemt nog "Louis" (de oorspronkelijke auteur).

# Functionele spec

De oorspronkelijke wensen van Ahmad per tab, in het Nederlands. Dit is het "wat"; hoe het eruitziet staat in de borden in [`design/boards/`](../design/boards) en in [`DESIGN.md`](DESIGN.md), de volgorde in [`ROADMAP.md`](ROADMAP.md).

Waar de app al bewust anders is gebouwd, staat dat eronder in een **Stand van zaken**-regel. Bij twijfel: vragen.

## Tabbalk (volgorde)

Links: **Home · Mail · Agenda · Focus · Muziek · Klembord · Notities · Systeem · Bestanden**
Rechts: **Instellingen** (open het Settings-venster).

## Tabs in detail

### Home
- Links groot vak **"Nu bezig"**: actieve IntelliJ-project (naam + branch), status "Verbonden · Xu Xm gefocust", knop "Open project".
- Rechts 2×2 compacte vakjes: **GitHub** (commits vandaag · open PR's), **WHOOP** (herstel %), **Muziek** (nummer · tijd), **Notion** (pagina's bijgewerkt). Welke vier, instelbaar in Settings.

> **Stand van zaken:** gebouwd (#4). "Nu bezig" werkt voor IntelliJ, Rider, VS Code en terminals. Het Muziek-vakje is live; GitHub, WHOOP en Notion staan nog op "Niet gekoppeld" (zie ROADMAP).

### Mail
- Bestaande Gmail-integratie, nieuw design.
- Bovenin rechts: filter **Alles / Ongelezen** + knop "Open in Gmail".
- Lijst-rijen (44 pt hoog): blauw stipje bij ongelezen · avatar met initiaal · afzender (vet als ongelezen) · onderwerp · tijd.
- Ongelezen-teller als badge op het tab-icoon.

> **Stand van zaken:** gebouwd (#6), alleen lezen via IMAP met een app-wachtwoord.

### Agenda & weer
- Bron: mijn agenda (mijn schoolrooster en diensten staan erin). **Voorkeur: EventKit** (macOS Agenda-app, die gesynct is met Google Calendar), zodat er geen extra API-key nodig is.
- Links: tijdlijn van vandaag. Afgelopen items doorgestreept/grijs, een rode **"nu"-lijn** met tijd, komende items met gekleurd streepje (dienst = oranje) en "over Xu Xm".
- Rechts: **weer** in Nijmegen (temperatuur + omschrijving) en een **vertrek-kaart** ("Vertrek voor je dienst 16:25 · 22 min reizen · droog tot 22:00"). Weer via Open-Meteo (gratis, geen key) of WeatherKit.

> **Stand van zaken:** gebouwd. EventKit en Open-Meteo. Een dienst is een afspraak met "dienst" in de titel, of (instelbaar) alles in één agenda. De reistijd is een vast aantal minuten in Settings: een route berekenen zou je adres naar een kaartdienst sturen. De plaats voor het weer is in Settings te kiezen (standaard Nijmegen). Staat er vandaag niets meer, dan toont de tijdlijn onder de nu-lijn alvast de eerste twee afspraken van morgen, onder *Morgen · vrijdag 30 oktober*. Wat nu bezig is staat in een eigen kaart met *NU*, de tijd die nog rest en een balk (bord 3.1).

### Focus-timer
- Ring met aftellende tijd, knoppen **Start/Pauze** en **Reset**, duur-keuze **25 / 50 / 90 min**.
- Opties: *Niet storen tijdens focus*, *Muziek starten bij begin*.
- Teller bovenin: "Vandaag X sessies · Xu Xm".
- Timer loopt door in de **ingeklapte notch** (kleine ring + tijd).

**Waar werk ik aan? (automatische taak-detectie), in deze volgorde:**
1. **Agenda:** is er nú een afspraak (les, stand-up, deadline-blok)? → gebruik die titel als taak. Dit dekt schooltijden.
2. **Actieve app + context** (buiten schooltijd):
   - `NSWorkspace.shared.frontmostApplication` voor de app.
   - IntelliJ / VS Code → **projectnaam** (via IntelliJ-integratie of venstertitel).
   - Browser → **site/tabblad** (Safari/Chrome via AppleScript; vraagt Automation-toestemming).
   - Notion / Word / Figma → **documentnaam** (venstertitel via Accessibility-toestemming).
3. **Leren van correcties:** past ik de taak handmatig aan, sla dan de koppeling op (bv. project `rihlah-app` → "Eigen app"). Volgende keer automatisch toepassen.
4. **Twijfel:** bij Start één keer vragen met 3–4 snelle knoppen (laatst gebruikte taken) + "Of typ zelf…".
- Onder de taaknaam staat altijd de **bron** met een stipje: "Uit agenda", "Automatisch · IntelliJ · rihlah-app" (groen) of "Zelf gekozen" (grijs).
- Op de taaknaam tikken (potlood-icoon) → taak kiezen of zelf typen.
- In Settings: lijst met koppelingen app/project → taak, aan te passen of te verwijderen.

> **Stand van zaken:** gebouwd. Taak uit de agenda of de app vooraan (met het Claude Code-project), correcties worden onthouden en staan in Settings → Focus. *Niet storen* werkt via twee eigen opdrachten in de Opdrachten-app ("wisp Focus On/Off"), omdat macOS apps geen focusmodus laat aanzetten. Browser-tabbladen en documentnamen (Accessibility/AppleScript) en de vraag bij twijfel zitten er nog niet in.

### Muziek
- Bestaande muziek-integratie, nieuw design.
- Links: albumhoes (120 pt), titel, artiest, voortgangsbalk met tijden, vorige / play-pauze / volgende, groene equalizer-balkjes als er iets speelt.
- Rechts: **"Hierna"** (volgende 2 nummers) + volumeschuif. Bovenin rechts: huidig audio-apparaat (bv. AirPods).

> **Stand van zaken:** gebouwd (#7, #9, #11), maar anders dan hierboven. "Hierna" kan niet (macOS geeft de wachtrij niet door); in plaats daarvan toont de rechterkaart een live spectrum (borden 9.1–9.6). Songteksten zijn geprobeerd en bewust weer weggehaald.

### Klembord
- Houdt de laatste ~20 gekopieerde items bij (`NSPasteboard.general.changeCount` pollen).
- **Sla nooit wachtwoorden op**: negeer items met type `org.nspasteboard.ConcealedType` / `TransientType` en items uit wachtwoordmanagers.
- Rij: type-label (URL / `</>` / Aa) · tekst (code in monospace) · hoe lang geleden · knop **Kopieer** (wordt kort "Gekopieerd" in accentkleur).
- Zoekveld rechtsboven in de tabbalk-rij.
- Alleen lokaal opslaan.

> **Stand van zaken:** gebouwd. Alleen tekst (geen afbeeldingen of bestanden). Elke seconde wordt één getal van het klembord gelezen (0,0 % CPU); de geschiedenis kan uit in Settings → Klembord, waar je haar ook wist.

### Notities
- Links: lijst met recente notities (tekst + tijd). Rechts: tekstveld "Typ een notitie…" + knop **Opslaan** → nieuwe notitie bovenaan.
- Lokaal opslaan (JSON in Application Support). **Later optioneel:** sync naar Notion via de bestaande Notion-integratie.

> **Stand van zaken:** gebouwd, lokaal (JSON). Klik op een notitie om hem te bewerken; rechtsklik om te kopiëren of te verwijderen. Sync naar Notion komt met de Notion-integratie.

### Systeem
- Vier vakken naast elkaar: **Batterij** (% + balk + resterende tijd), **AirPods** (links/rechts/case %; best effort, mag weggelaten worden als het niet betrouwbaar lukt), **CPU** (% + mini-grafiek + grootste verbruiker), **Opslag** (vrij van totaal + balk).
- Rechtsboven: huidige Wi-Fi-naam.

> **Stand van zaken:** gebouwd. AirPods via `system_profiler` (best effort, alleen als ze verbonden zijn). De wifinaam geeft macOS alleen met locatietoegang; die vraag je in Settings → Systeem, anders staat er "Wi‑Fi".

### Bestanden
- Bestaande drop zone behouden, alleen restylen (zonder mascotte).

## Ingeklapte notch & meldingen

**Ingeklapt (live activities)**, zoals nu, maar strakker:
- **Muziek speelt:** albumhoesje links, groene equalizer-balkjes rechts (bestaand gedrag behouden).
- **Ongelezen mail:** mail-icoon links, rood badge met aantal rechts.
- **Focus loopt:** kleine voortgangsring + resterende tijd.

**Melding nieuwe mail (peek):**
- Notch klapt kort uit tot ~420 pt breed: avatar, afzender, "nu", onderwerp + eerste regel.
- Drie knoppen: **Openen** (wit, primair) · **Verwijderen** (naar de Gmail-prullenbak, niet permanent) · **Later** (melding weg, mail blijft ongelezen).
- Sluit automatisch weer (bestaande "close after X s" instelling).

> **Stand van zaken:** gebouwd. De peek toont het onderwerp, niet de eerste regel (wisp haalt alleen headers op). *Verwijderen* verplaatst naar de Gmail-prullenbak. Beide (peek en aantal op de dichte notch) zijn uit te zetten in Settings → Gmail. Tijdens focus met *Niet storen* komt er geen peek.

## Settings-aanpassingen

> **Stand van zaken:** accentkleur, sluitvertraging, geluiden, opstarten bij inloggen, Gmail, Agenda & weer (agenda's, diensten, reistijd, plaats), Muziek (spectrum), Claude Code-hooks en de taal (Engels of Nederlands, standaard die van macOS) zijn er. Tabs, Focus, integraties en hotkey nog niet.

- Bovenaan: accentkleur kiezen (4 opties).
- Sectie **Tabs**: tabs aan/uit en volgorde.
- Sectie **Focus**: standaardduur, Niet storen aan/uit, koppelingen app/project → taak.
- Sectie **Agenda**: welke agenda's meetellen.
- Bestaande secties (integraties, sound, behavior, active pills, hotkey, startup) blijven.
- Venstertitel wordt "Settings — wisp".

## Toestemmingen (macOS)

Vraag pas toestemming op het moment dat een functie het nodig heeft, met uitleg:
- **Agenda** (EventKit) voor Agenda + Focus-detectie
- **Accessibility** voor venstertitels (documentnaam)
- **Automation** voor browser-tabblad (Safari/Chrome)
- Locatie is niet nodig: weer voor Nijmegen mag vast ingesteld of in Settings te kiezen zijn.


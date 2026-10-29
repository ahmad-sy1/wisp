# Coucou: designbrief

## Wat is het?
Coucou is een native macOS-app (Swift/SwiftUI) die in de **notch van de MacBook** woont, vergelijkbaar met de Dynamic Island van de iPhone. Er woont een klein geanimeerd figuurtje in, **Mochi**: een zacht, wit "marshmallow"-blobje met ogen en blosjes. De kleur van Mochi verandert met de status.

De app doet drie dingen:
1. **Claude Code volgen.** Je ziet live wat de AI-codeerassistent doet (stappen, "denkt na", "klaar", "fout"). Als Claude Code toestemming vraagt voor een commando, kun je die rechtstreeks vanuit de notch geven of weigeren.
2. **Integraties tonen** als kleine kaartjes: GitHub, Notion, WHOOP (herstel, strain en slaap), Muziek (wat er nu speelt, ook YouTube in de browser), plus optioneel Vercel, Stripe, Cal.com, n8n en Resend. Er staan maximaal 4 tegelijk aan.
3. **Snelle acties**: chatten met Mochi, een bestand op de notch slepen om het te uploaden of te mailen, en de IDE (IntelliJ) openen.

## Vaste randvoorwaarden (niet veranderen)
- **Vorm**: een zwart (`#000`) eiland dat naadloos overloopt in de fysieke notch. De bovenkant is recht (die zit tegen de schermrand), de onderhoeken zijn afgerond. Het moet eruitzien alsof de notch zelf groter wordt.
- **Breedte als hij open is**: 640 pt. De hoogte hangt af van de weergave, meestal 160 pt (mail 240 en chat tot 300).
- **Dicht** is de notch precies zo groot als de echte notch, ongeveer 184 × 32 pt. Alles rondom is doorzichtig en klikken gaan erdoorheen.
- **Mochi wordt met code getekend** (vormen en gradiënten), dus niet met afbeeldingen of Lottie. Een ontwerp moet je met SwiftUI-vormen kunnen namaken.
- **Donker thema** dat over elke achtergrond heen moet werken: de menubalk, video's, lichte apps.
- **Subtiele animaties.** De gebruiker wil geen gewiebel heen en weer, alleen een rustige veer bij hover en bij openen en sluiten.

## Toestanden van het eiland
| Toestand | Grootte | Wat je ziet |
|---|---|---|
| **Dicht** (hidden) | notch-formaat | niets: de notch ziet er normaal uit |
| **Dicht + hover** | +18 × 7 pt | de notch "popt" net iets groter |
| **Dicht + muziek speelt** *(nieuw)* | notch + ±38 pt aan elke kant | links de albumhoes of video-thumbnail, rechts 4 bewegende equalizer-balkjes in de kleur van de hoes (zoals de iPhone) |
| **Compact** | notch + 160 pt | Mochi links, een 2×2-raster met mini-Mochi's van andere sessies rechts |
| **Open** (expanded) | 640 × 160+ | een header met tabbladen en daaronder de inhoud |

## Weergaven als hij open is
- **Header** (34 pt): links pill-tabbladen (home, chat, +). Rechts de instellingen en een geluidsknop.
- **Overzicht**: een grote Mochi links (±58 pt), daarnaast de huidige sessie (projectnaam met gekleurde stip, plus stappen met icoontjes). Rechts staan "pills" voor andere sessies en integraties: een capsule met een mini-Mochi in de projectkleur.
- **Toestemming**: "Claude Code wil een commando uitvoeren", het commando in een monospace-blok, en de knoppen *Weigeren (N)*, *Altijd toestaan* en *Toestaan (Y)*. De primaire knop is wit en heeft de vorm van een pil.
- **Vraag / Fout / Klaar / Verward**: varianten met Mochi in de bijbehorende stemming.
- **Upload**: je sleept een bestand naar de notch. Mochi "eet" het op, er loopt een voortgangsbalk en daarna kies je *mailen* of *bewaren*.
- **Mail / Notitie / Chat**: tekstvelden in het eiland.
- **Integratiekaartjes**: GitHub-statistieken, Notion-pagina's, de WHOOP-recovery-ring, een muziekspeler (hoes, titel, artiest, vorige/play/volgende), enzovoort.
- **Begroeting**: een korte animatie waarin Mochi zwaait.

## Mochi: stemmingen
idle, working (blauw `#3B9EFF`), thinking (paars `#A78BFA`), searching (indigo `#6366F1`), approval (oranje `#F5A524`), error (rood `#F4505E`), finished (groen `#34D399`), rate limit (`#F59E0B`), sleeping, dizzy. Plus de emotes love, surprised, proud, wink, yawn, happy en annoyed. Mochi volgt de muis met zijn ogen.

## Huidige stijl
- Achtergrond `#000`, kaartjes iets lichter (±`#141518`) met een radius van 20 pt.
- Tekst: primair `#F5F6F8`, secundair `#8E939C`, gedimd `#6B7079`.
- Systeemfont (SF Pro), meestal 11 tot 13 pt, en monospace voor commando's.
- Accenten: groen `#22C55E`, rood `#F4505E`, plus een eigen kleur per project of integratie.

## Waar ik hulp bij wil
- Een **frissere, meer verfijnde look** voor de geopende notch, in de geest van Apple en de Dynamic Island, maar mét Mochi als persoonlijkheid.
- **Meer samenhang tussen de integratiekaartjes.** Ze zijn nu los van elkaar ontstaan en zien er allemaal anders uit.
- **Een duidelijke hiërarchie**: wat is urgent (toestemming, fout) en wat is alleen info?
- **De "live activity" in de dichte notch** (muziek, en mogelijk ook "Claude is bezig") nog mooier maken.
- Graag ontwerpen op **echte maat in punten** (640 breed, de notch ±184 × 32), zodat ik ze 1-op-1 in SwiftUI kan bouwen.

## Bijlagen
- `design/captures/*.png`: schermafbeeldingen van de huidige weergaven en van Mochi in elke stemming.
- `design/prototype/notch-buddy.html`: het originele HTML-prototype (de visuele referentie).

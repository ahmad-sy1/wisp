# wisp

Een klein lichtje bovenin je scherm: een macOS-app in de notch met je Claude Code-sessies, mail, agenda, focus-timer, muziek, klembord, notities en systeeminfo.

## Bouwen

Vereist Xcode en [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen
xcodebuild -scheme wisp -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/wisp.app
```

## Installeren en releasen

- `./scripts/install.sh` bouwt een Release-versie en zet die in `/Applications` (vervangt de draaiende wisp).
- `./scripts/release.sh` maakt een ondertekende en door Apple genotariseerde release op GitHub. De versie komt uit `MARKETING_VERSION` in `project.yml`; eenmalige setup staat bovenin het script.
- Elke push en PR naar `main` wordt op GitHub Actions gebouwd (workflow *Build*).

## Regels

- Swift 6, SwiftUI + AppKit, geen dependencies van derden.
- Geheimen alleen in de Keychain, nooit in code of git.
- Geen telemetrie. Netwerk alleen naar diensten die je zelf instelt.
- 0 % CPU als de notch dicht is.

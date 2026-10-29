# wisp

Een klein lichtje bovenin je scherm: een macOS-app in de notch met je Claude Code-sessies, mail, agenda, focus-timer, muziek, klembord, notities en systeeminfo.

## Bouwen

Vereist Xcode en [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen
xcodebuild -scheme wisp -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/wisp.app
```

## Regels

- Swift 6, SwiftUI + AppKit, geen dependencies van derden.
- Geheimen alleen in de Keychain, nooit in code of git.
- Geen telemetrie. Netwerk alleen naar diensten die je zelf instelt.
- 0 % CPU als de notch dicht is.

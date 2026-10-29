import SwiftUI

/// Settings → Muziek: lyrics lookup and spectrum access.
struct MusicSection: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var spectrum: Spectrum

    var body: some View {
        Section("Muziek") {
            Toggle("Songteksten tonen", isOn: $prefs.lyricsEnabled)
            Text("Zoekt tijdgesynchroniseerde teksten op bij LRCLIB (lrclib.net). Alleen artiest, titel, album en duur worden verstuurd; teksten worden lokaal bewaard.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Live spectrum", isOn: Binding(
                get: { spectrum.consent == .allowed },
                set: { $0 ? spectrum.allow() : spectrum.decline() }
            ))
            Text("Analyseert live het geluid van wat er speelt. Er wordt niets opgenomen, opgeslagen of verstuurd. macOS vraagt de eerste keer om toestemming voor systeemaudio.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

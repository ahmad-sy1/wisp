import SwiftUI

/// Settings → Muziek: access for the live spectrum.
struct MusicSection: View {
    @ObservedObject var spectrum: Spectrum

    var body: some View {
        Section("Muziek") {
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

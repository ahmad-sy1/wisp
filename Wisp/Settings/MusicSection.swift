import SwiftUI

/// Settings → Music: access for the live spectrum.
struct MusicSection: View {
    @ObservedObject var spectrum: Spectrum

    var body: some View {
        Section("Music") {
            Toggle("Live spectrum", isOn: Binding(
                get: { spectrum.consent == .allowed },
                set: { $0 ? spectrum.allow() : spectrum.decline() }
            ))
            Text("Analyses the sound of what plays, live. Nothing is recorded, stored or sent. macOS asks for permission for system audio the first time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

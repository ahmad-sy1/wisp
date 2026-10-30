import SwiftUI

/// Settings → Music (board 10.5): the live spectrum and the system-audio permission.
/// The mini spectrum, battery saver and sources follow in #26.
struct MusicPage: View {
    @ObservedObject var spectrum: Spectrum

    var body: some View {
        SettingsPage(title: String(localized: "Music"),
                     note: String(localized: "The spectrum analyses the sound of what plays, live. Nothing is recorded, stored or sent.")) {
            SettingsGroup(header: String(localized: "Spectrum")) {
                SettingsToggle(String(localized: "Live spectrum"),
                               subtitle: String(localized: "Bars that move with the music in the Music tab"),
                               isOn: Binding(get: { spectrum.consent == .allowed },
                                             set: { $0 ? spectrum.allow() : spectrum.decline() }))
            }

            SettingsGroup(header: String(localized: "Permission")) {
                SettingsRow(title: String(localized: "System audio")) {
                    // macOS doesn't tell apps whether it granted system audio, so this
                    // shows wisp's own switch; macOS asks the first time the spectrum runs.
                    if spectrum.consent == .allowed {
                        SettingsStatus(text: String(localized: "On"), color: Theme.ok)
                    } else {
                        SettingsStatus(text: String(localized: "Off"), color: Theme.textSecondary)
                    }
                } trailing: {
                    Button("Open in System Settings") { Self.openPrivacySettings() }
                        .buttonStyle(.settings)
                }
                .padding(.vertical, 6)
            }
        }
    }

    private static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

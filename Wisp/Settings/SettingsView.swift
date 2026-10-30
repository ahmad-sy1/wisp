import SwiftUI

struct SettingsView: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section {
                LabeledContent("Accent colour") {
                    HStack(spacing: 10) {
                        ForEach(Accent.allCases) { accent in
                            AccentSwatch(color: accent.color, selected: prefs.accent == accent) {
                                prefs.accent = accent
                            }
                        }
                    }
                }
            }

            Section("Behaviour") {
                LabeledContent("Close after leaving") {
                    HStack {
                        Slider(value: $prefs.closeDelay, in: 0.2...5, step: 0.1)
                            .frame(width: 160)
                        Text(String(format: "%.1f s", prefs.closeDelay))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle("Sounds", isOn: $prefs.soundsEnabled)
                Picker("Language", selection: $prefs.language) {
                    Text("Same as macOS").tag(AppLanguage.system)
                    // Each language in its own words.
                    Text(verbatim: "English").tag(AppLanguage.english)
                    Text(verbatim: "Nederlands").tag(AppLanguage.dutch)
                }
                if prefs.language != prefs.launchLanguage {
                    LabeledContent("Restart wisp to switch language.") {
                        Button("Restart") { prefs.relaunch() }
                    }
                    .font(.caption)
                }
                Toggle("Open at login", isOn: Binding(
                    get: { prefs.launchAtLogin },
                    set: { prefs.setLaunchAtLogin($0) }
                ))
            }

            GmailSection(store: .shared)

            AgendaSection(agenda: .shared, weather: .shared)

            MusicSection(spectrum: .shared)

            ClaudeHooksSection()
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AccentSwatch: View {
    let color: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(.white, lineWidth: selected ? 2 : 0))
                .padding(2)
                .overlay(Circle().strokeBorder(color.opacity(selected ? 0.6 : 0), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

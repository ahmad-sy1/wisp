import SwiftUI

/// Settings → General (board 10.2): language and accent, behaviour, Claude Code hooks.
struct GeneralPage: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        SettingsPage(title: String(localized: "General")) {
            SettingsGroup(header: String(localized: "Language & appearance")) {
                SettingsRow(String(localized: "Language"), subtitle: languageSubtitle) {
                    HStack(spacing: 8) {
                        if prefs.language != prefs.launchLanguage {
                            Button("Restart") { prefs.relaunch() }
                                .buttonStyle(.settings)
                        }
                        Picker("Language", selection: $prefs.language) {
                            Text("Same as macOS (\(Self.systemLanguageName))").tag(AppLanguage.system)
                            // Each language in its own words.
                            Text(verbatim: "English").tag(AppLanguage.english)
                            Text(verbatim: "Nederlands").tag(AppLanguage.dutch)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                SettingsRow(String(localized: "Accent colour")) {
                    HStack(spacing: 10) {
                        ForEach(Accent.allCases) { accent in
                            AccentSwatch(color: accent.color, selected: prefs.accent == accent) {
                                prefs.accent = accent
                            }
                        }
                    }
                }
            }

            SettingsGroup(header: String(localized: "Behaviour")) {
                SettingsRow(String(localized: "Close after leaving")) {
                    HStack(spacing: 14) {
                        // Rounded by hand: a stepped slider draws a tick per step.
                        Slider(value: Binding(get: { prefs.closeDelay },
                                              set: { prefs.closeDelay = ($0 * 10).rounded() / 10 }),
                               in: 0.2...5)
                            .frame(width: 260)
                        Text(String(format: "%.1f s", prefs.closeDelay))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                SettingsToggle(String(localized: "Sounds"),
                               subtitle: String(localized: "A soft sound with notifications"),
                               isOn: $prefs.soundsEnabled)
                SettingsToggle(String(localized: "Open at login"),
                               subtitle: String(localized: "wisp starts with your Mac"),
                               isOn: Binding(get: { prefs.launchAtLogin },
                                             set: { prefs.setLaunchAtLogin($0) }))
            }

            ClaudeHooksGroup()
        }
    }

    private var languageSubtitle: String {
        prefs.language != prefs.launchLanguage
            ? String(localized: "Restart wisp to switch language.")
            : String(localized: "For the notch and this window")
    }

    /// The language macOS would give wisp, among the ones wisp ships.
    private static var systemLanguageName: String {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
        let language = global?.lazy.compactMap(AppLanguage.init(code:)).first ?? .english
        return language == .dutch ? "Nederlands" : "English"
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
                .frame(width: 16, height: 16)
                .padding(3)
                .overlay(Circle().strokeBorder(selected ? .white : color, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

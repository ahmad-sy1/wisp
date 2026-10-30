import SwiftUI

/// Settings → Focus (board 10.6): the timer's defaults and the tasks wisp learned from
/// your corrections. Adding rules yourself follows in #27.
struct FocusPage: View {
    @ObservedObject var focus: FocusStore

    var body: some View {
        SettingsPage(title: String(localized: "Focus"),
                     note: String(localized: "When you change a task in the notch, wisp remembers it here as “Learned”. You can always remove a rule.")) {
            SettingsGroup(header: String(localized: "Timer")) {
                SettingsRow(String(localized: "Default duration")) {
                    DurationPicker(minutes: $focus.minutes)
                }
                SettingsToggle(String(localized: "Do not disturb during focus"),
                               subtitle: String(localized: "Runs your Shortcuts “\(FocusStore.shortcutOn)” and “\(FocusStore.shortcutOff)”"),
                               isOn: $focus.doNotDisturb)
                SettingsToggle(String(localized: "Start music when a session begins"), isOn: $focus.startMusic)
            }

            SettingsGroup(header: String(localized: "Recognising the task · your calendar first, then the app you use")) {
                if focus.learned.isEmpty {
                    SettingsRow(String(localized: "No rules yet"),
                                subtitle: String(localized: "Change a task the timer guessed and wisp remembers it for that app or project."))
                        .padding(.vertical, 6)
                } else {
                    ForEach(focus.learned.keys.sorted(), id: \.self) { key in
                        RuleRow(source: Self.describe(key), task: focus.learned[key] ?? "") {
                            focus.forget(key)
                        }
                    }
                }
            }
        }
    }

    /// "com.jetbrains.intellij|wisp" → "IntelliJ IDEA · wisp".
    private static func describe(_ key: String) -> String {
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        let bundle = parts.first ?? key
        let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            ?? bundle
        return parts.count > 1 ? "\(app) · \(parts[1])" : app
    }
}

/// *25 min · 50 min · 90 min*, the active one on a grey pill.
private struct DurationPicker: View {
    @Binding var minutes: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(FocusStore.durations, id: \.self) { value in
                let active = value == minutes
                Button { minutes = value } label: {
                    Text("\(value) min")
                        .font(.system(size: 13, weight: active ? .semibold : .regular))
                        .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                        .frame(width: 60, height: 26)
                        .background(RoundedRectangle(cornerRadius: 6).fill(active ? Theme.activeTab : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.control))
    }
}

/// "IntelliJ IDEA · wisp → Own app · Learned ✕".
private struct RuleRow: View {
    let source: String
    let task: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: source)
                .font(.system(size: 13.5))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 40)
            Text(verbatim: task)
                .font(.system(size: 13.5, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Learned")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 110, alignment: .leading)
            RemoveButton(help: String(localized: "Remove"), action: remove)
        }
        .padding(.leading, 15)
        .padding(.trailing, 10)
        .frame(height: 44)
    }
}

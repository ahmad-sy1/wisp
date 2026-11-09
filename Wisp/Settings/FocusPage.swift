import SwiftUI

/// Settings → Focus (board 10.6): the timer's defaults, and which task an app or project
/// means: learned from your corrections or added here.
struct FocusPage: View {
    @ObservedObject var focus: FocusStore
    @State private var adding = false

    var body: some View {
        SettingsPage(
            title: String(localized: "Focus"),
            note: String(
                localized: "When you change a task in the notch, wisp remembers it here as “Learned”. You can always remove a rule.")
        ) {
            SettingsGroup(header: String(localized: "Timer")) {
                SettingsRow(
                    String(localized: "Default duration"),
                    subtitle: focus.isActive ? String(localized: "Can't change while a session runs") : nil
                ) {
                    DurationPicker(minutes: $focus.minutes)
                        .disabled(focus.isActive)
                }
                SettingsToggle(
                    String(localized: "Do not disturb during focus"),
                    subtitle: String(localized: "Runs your Shortcuts “\(FocusStore.shortcutOn)” and “\(FocusStore.shortcutOff)”"),
                    isOn: $focus.doNotDisturb)
                SettingsToggle(String(localized: "Start music when a session begins"), isOn: $focus.startMusic)
            }

            SettingsGroup(header: String(localized: "Recognising the task · your calendar first, then the app you use")) {
                if focus.rules.isEmpty && !adding {
                    SettingsRow(
                        String(localized: "No rules yet"),
                        subtitle: String(localized: "Change a task the timer guessed and wisp remembers it for that app or project.")
                    )
                    .padding(.vertical, 6)
                } else {
                    ForEach(focus.rules) { rule in
                        RuleRow(
                            source: Self.describe(rule.key), task: rule.task,
                            origin: rule.isOwn ? String(localized: "Set by you") : String(localized: "Learned")
                        ) {
                            focus.forget(rule.key)
                        }
                    }
                }
                if adding {
                    AddRuleForm(cancel: { adding = false }) { bundle, project, task in
                        focus.addRule(bundle: bundle, project: project, task: task)
                        adding = false
                    }
                } else {
                    SettingsLinkRow(title: String(localized: "+ Add rule")) { adding = true }
                }
            }
        }
    }

    /// "com.jetbrains.intellij|wisp" → "IntelliJ IDEA · wisp".
    private static func describe(_ key: String) -> String {
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        let bundle = parts.first ?? key
        let app =
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            ?? bundle
        return parts.count > 1 ? "\(app) · \(parts[1])" : app
    }
}

/// *25 min · 50 min · 90 min*, the active one on a grey pill.
private struct DurationPicker: View {
    @Binding var minutes: Int

    var body: some View {
        SegmentedControl(
            selection: $minutes,
            values: FocusStore.durations,
            title: { String(localized: "\($0) min") },
            segmentWidth: 60)
    }
}

/// "IntelliJ IDEA · wisp → Own app · Learned ✕".
private struct RuleRow: View {
    let source: String
    let task: String
    let origin: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: source)
                .font(.system(size: 13.5))
                .lineLimit(1)
                .help(source)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 40)
            Text(verbatim: task)
                .font(.system(size: 13.5, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: origin)
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

/// The new rule, inline in the card: which app, optionally which project, which task.
private struct AddRuleForm: View {
    let cancel: () -> Void
    let add: (_ bundle: String, _ project: String, _ task: String) -> Void

    private struct App: Equatable {
        let bundle: String
        let name: String
    }

    @State private var app: App?
    @State private var project = ""
    @State private var task = ""

    /// The apps that run now; others through *Other…*.
    private var running: [App] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { running in
                running.bundleIdentifier.map { App(bundle: $0, name: running.localizedName ?? $0) }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var canAdd: Bool {
        app != nil && !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Menu(app?.name ?? String(localized: "Choose an app")) {
                    ForEach(running, id: \.bundle) { candidate in
                        Button(candidate.name) { app = candidate }
                    }
                    Divider()
                    Button("Other…") { chooseOther() }
                }
                .fixedSize()
                TextField("Project (optional)", text: $project)
                    .textFieldStyle(.roundedBorder)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                TextField("Task", text: $task)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if canAdd, let app { add(app.bundle, project, task) } }
            }
            HStack(spacing: 8) {
                Text("The project is the one Claude Code works in.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button("Cancel", action: cancel)
                    .buttonStyle(.settings)
                Button("Add") { if let app { add(app.bundle, project, task) } }
                    .buttonStyle(.settings)
                    .disabled(!canAdd)
            }
        }
        .padding(15)
    }

    private func chooseOther() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { response in
            guard response == .OK, let url = panel.url, let bundle = Bundle(url: url)?.bundleIdentifier else { return }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            MainActor.assumeIsolated { app = App(bundle: bundle, name: name) }
        }
    }
}

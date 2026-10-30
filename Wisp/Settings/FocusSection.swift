import SwiftUI

/// Settings → Focus: the tasks wisp learned from your corrections, and how
/// "Do not disturb" works.
struct FocusSection: View {
    @ObservedObject var focus: FocusStore

    var body: some View {
        Section("Focus") {
            if focus.learned.isEmpty {
                Text("When you change a task the timer guessed, wisp remembers it for that app or project.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(focus.learned.keys.sorted(), id: \.self) { key in
                    LabeledContent {
                        Button("Forget") { focus.forget(key) }
                    } label: {
                        Text(verbatim: "\(Self.describe(key)) → \(focus.learned[key] ?? "")")
                    }
                }
            }
            Text("“Do not disturb during focus” runs your Shortcuts “\(FocusStore.shortcutOn)” and “\(FocusStore.shortcutOff)”. Make them in the Shortcuts app with the action Set Focus.")
                .font(.caption)
                .foregroundStyle(.secondary)
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

import SwiftUI

/// Settings → Clipboard: the history on or off, and clearing it.
struct ClipboardSection: View {
    @ObservedObject var clipboard: ClipboardStore

    var body: some View {
        Section("Clipboard") {
            Toggle("Keep a clipboard history", isOn: $clipboard.isEnabled)
            LabeledContent("History") {
                Button("Clear") { clipboard.clear() }
                    .disabled(clipboard.items.isEmpty)
            }
            Text("The last \(ClipboardStore.limit) texts you copied, stored only on this Mac. Passwords and one-time codes that apps mark as such are never kept.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

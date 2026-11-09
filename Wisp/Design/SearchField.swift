import SwiftUI

/// A search box with a clear button and its shortcut (board 0.2).
struct SearchField: View {
    @Binding var text: String
    let prompt: String
    var shortcut: String = "⌘K"
    var isFocused: FocusState<Bool>.Binding

    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused(isFocused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel("Clear search")
            }
            Text(verbatim: shortcut)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 5)
                .frame(height: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Theme.lineStrong, lineWidth: 1)
                )
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                .fill(Theme.control)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                .strokeBorder(isFocused.wrappedValue ? prefs.accent.color : Theme.lineStrong, lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: Theme.buttonCorner + 2, style: .continuous)
                .stroke(prefs.accent.color.opacity(isFocused.wrappedValue ? 0.3 : 0), lineWidth: 3)
                .padding(-1)
        )
    }
}

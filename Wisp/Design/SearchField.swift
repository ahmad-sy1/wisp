import SwiftUI

/// A search box with a clear button and its shortcut (board 0.2).
struct SearchField: View {
    @Binding var text: String
    let prompt: String
    var shortcut: String = "⌘K"
    var isFocused: FocusState<Bool>.Binding

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
        .fieldChrome(focused: isFocused.wrappedValue)
    }
}

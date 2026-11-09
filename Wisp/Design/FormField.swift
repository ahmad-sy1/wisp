import SwiftUI

extension View {
    /// The box around a field: a blue ring with focus, red on an error (board 0.2).
    func fieldChrome(focused: Bool, failed: Bool = false, locked: Bool = false) -> some View {
        modifier(FieldChrome(focused: focused, failed: failed, locked: locked))
    }
}

private struct FieldChrome: ViewModifier {
    let focused: Bool
    let failed: Bool
    let locked: Bool

    @ObservedObject private var prefs = Preferences.shared

    private var border: Color {
        if failed { return Theme.badge }
        return focused ? prefs.accent.color : locked ? Theme.cardBorder : Theme.lineStrong
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                    .fill(locked ? Theme.rowHover : Theme.control)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .background(
                RoundedRectangle(cornerRadius: Theme.buttonCorner + 2, style: .continuous)
                    .stroke(prefs.accent.color.opacity(focused && !failed ? 0.3 : 0), lineWidth: 3)
                    .padding(-1)
            )
    }
}

/// A labelled text or secret field (board 0.2).
struct FormField: View {
    let label: String
    @Binding var text: String
    let prompt: String
    var isSecret = false
    var error: String?
    /// Read-only, while checking or once connected.
    var isLocked = false
    /// Connected: only dots, the secret is never loaded back.
    var isMasked = false

    @State private var revealed = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textLabel)
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    // Drawn here: a field's own prompt takes the field's text colour.
                    if text.isEmpty && !isMasked {
                        Text(prompt).font(.system(size: 13)).foregroundStyle(Theme.textFaint).lineLimit(1).allowsHitTesting(false)
                    }
                    input
                }
                trailing
            }
            .fieldChrome(focused: focused, failed: error != nil, locked: isLocked)
            if let error {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 11))
                    Text(error).fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.redText)
            }
        }
    }

    @ViewBuilder private var input: some View {
        if isMasked {
            Text(verbatim: "••••••••••••••••")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if isSecret && !revealed {
            SecureField(label, text: $text, prompt: Text(verbatim: ""))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(isLocked ? Theme.textSecondary : Theme.textPrimary)
                .focused($focused)
                .disabled(isLocked)
        } else {
            TextField(label, text: $text, prompt: Text(verbatim: ""))
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: isSecret ? .monospaced : .default))
                .foregroundStyle(isLocked ? Theme.textSecondary : Theme.textPrimary)
                .focused($focused)
                .disabled(isLocked)
        }
    }

    @ViewBuilder private var trailing: some View {
        if isMasked {
            Text("Hidden")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textFaint)
        } else if isSecret && !isLocked {
            Button {
                revealed.toggle()
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel(revealed ? String(localized: "Hide key") : String(localized: "Show key"))
        }
    }
}

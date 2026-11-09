import SwiftUI

/// A pill that filters a list by category, with how many it would show (board 0.2).
struct FilterChip: View {
    let title: String
    let count: Int
    let active: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    private var foreground: Color {
        if !isEnabled { return Theme.textDisabled }
        return active ? .black : Theme.textLabel
    }

    private var fill: Color {
        if active { return .white }
        return hovered && isEnabled ? Theme.rowHover : .clear
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title).fontWeight(active ? .semibold : .regular)
                Text(verbatim: "\(count)")
                    .monospacedDigit()
                    .foregroundStyle(active ? Color.black.opacity(0.5) : Theme.textFaint)
            }
            .font(.system(size: 12))
            .foregroundStyle(foreground)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(Capsule().fill(fill))
            .overlay(Capsule().inset(by: 0.5).stroke(active ? .clear : Theme.lineStrong, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovered = $0 }
    }
}

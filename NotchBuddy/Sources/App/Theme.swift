import SwiftUI

// MARK: - wisp design tokens
//
// Single source for the redesign's colours and sizes (see REDESIGN-WISP.md §3).
// Pure black panel, flat cards, no gradients, no glass.

enum Wisp {
    // Colours
    static let panel        = Color(hex: "#000000")
    static let card         = Color(hex: "#141416")
    static let cardBorder   = Color(hex: "#1F1F22")
    static let control      = Color(hex: "#1C1C1E")
    static let controlHover = Color(hex: "#222225")
    static let activeTab    = Color(hex: "#2A2A2D")
    static let textPrimary  = Color(hex: "#FFFFFF")
    static let textSecondary = Color(hex: "#A1A1AA")
    static let badge        = Color(hex: "#FF453A")
    static let ok           = Color(hex: "#30D158")
    static let warning      = Color(hex: "#FF9F0A")

    /// Accent options offered in Settings; the first is the default.
    static let accentOptions = ["#0A84FF", "#30D158", "#FF9F0A", "#BF5AF2"]
    static let accentKey = "wispAccent"

    static var accent: Color {
        Color(hex: UserDefaults.standard.string(forKey: accentKey) ?? accentOptions[0])
    }

    // Panel geometry (expanded)
    static let panelWidth: CGFloat     = 600
    static let panelTopInset: CGFloat  = 40
    static let panelSideInset: CGFloat = 14
    static let panelCorner: CGFloat    = 26
    static let contentHeight: CGFloat  = 150
    static let panelHeight: CGFloat    = 245

    // Shapes
    static let cardCorner: CGFloat   = 16
    static let buttonCorner: CGFloat = 9
    static let buttonHeight: CGFloat = 28
    static let tabSize = CGSize(width: 32, height: 28)

    // Type
    static func title(_ size: CGFloat = 14) -> Font { .system(size: size, weight: .semibold) }
    static func label(_ size: CGFloat = 12) -> Font { .system(size: size) }
    static func meta(_ size: CGFloat = 10.5) -> Font { .system(size: size) }
}

// MARK: - Status glyph (replaces the Mochi mascot)

extension BotState {
    /// Line icon shown wherever the mascot used to be.
    var symbol: String {
        switch self {
        case .idle:      return "circle"
        case .working:   return "chevron.left.forwardslash.chevron.right"
        case .thinking:  return "ellipsis"
        case .searching: return "magnifyingglass"
        case .approval:  return "hand.raised"
        case .question:  return "questionmark"
        case .error:     return "exclamationmark.triangle"
        case .finished:  return "checkmark"
        case .ratelimit: return "hourglass"
        case .sleeping:  return "moon"
        case .dizzy:     return "circle"
        }
    }

    var tint: Color {
        switch self {
        case .approval, .question, .ratelimit: return Wisp.warning
        case .error:    return Wisp.badge
        case .finished: return Wisp.ok
        case .working, .thinking, .searching: return Wisp.accent
        default:        return Wisp.textPrimary
        }
    }
}

/// Rounded tile with a line icon for the current state.
struct StatusGlyph: View {
    let state: BotState
    var size: CGFloat = 52

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(Wisp.control)
            .overlay(
                Image(systemName: state.symbol)
                    .font(.system(size: size * 0.36, weight: .regular))
                    .foregroundColor(state.tint)
                    .contentTransition(.symbolEffect(.replace))
            )
            .frame(width: size, height: size)
            .animation(.easeInOut(duration: 0.25), value: state)
    }
}

/// Small coloured dot for a task (pills, compact grid, column).
struct TaskDot: View {
    let task: AgentTask
    var size: CGFloat = 8

    private var busy: Bool {
        [.working, .thinking, .searching].contains(task.state)
    }

    var body: some View {
        Circle()
            .fill(Color(hex: task.color))
            .frame(width: size, height: size)
            .opacity(task.state == .sleeping ? 0.4 : 1)
            .overlay(
                Circle()
                    .stroke(Color(hex: task.color).opacity(0.35), lineWidth: 1)
                    .frame(width: size + 5, height: size + 5)
                    .opacity(busy ? 1 : 0)
            )
    }
}

/// The wisp mark: a white dot inside an accent ring.
struct WispMark: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle().stroke(Wisp.accent.opacity(0.35), lineWidth: size * 0.05)
            Circle().stroke(Wisp.accent, lineWidth: size * 0.09)
                .padding(size * 0.14)
            Circle().fill(Color.white)
                .padding(size * 0.33)
        }
        .frame(width: size, height: size)
    }
}

import SwiftUI

/// The button variants of board 0.2. Hover goes one step up the grey ladder, pressing
/// one step back; a disabled button loses its colour.
private enum ButtonPhase {
    case normal, hovered, pressed, disabled
}

private struct PhasedLabel: View {
    let configuration: ButtonStyleConfiguration
    let weight: Font.Weight
    let height: CGFloat
    let text: (ButtonPhase) -> Color
    let fill: (ButtonPhase) -> Color

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    private var phase: ButtonPhase {
        if !isEnabled { return .disabled }
        if configuration.isPressed { return .pressed }
        return hovered ? .hovered : .normal
    }

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: weight))
            .foregroundStyle(text(phase))
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                    .fill(fill(phase))
            )
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
    }
}

/// Primary: the one next step in a view (*Open project*, *Connect*).
struct AccentButtonStyle: ButtonStyle {
    var height = Theme.buttonHeight

    func makeBody(configuration: Configuration) -> some View {
        AccentLabel(configuration: configuration, height: height)
    }

    private struct AccentLabel: View {
        let configuration: ButtonStyleConfiguration
        let height: CGFloat
        @ObservedObject private var prefs = Preferences.shared

        var body: some View {
            PhasedLabel(
                configuration: configuration,
                weight: .semibold,
                height: height,
                text: { $0 == .disabled ? Theme.textDisabled : .white },
                fill: { phase in
                    switch phase {
                    case .normal: prefs.accent.color
                    case .hovered: prefs.accent.hover
                    case .pressed: prefs.accent.pressed
                    case .disabled: Theme.control
                    }
                })
        }
    }
}

/// Secondary: every other action (*Manage*, *Cancel*).
struct SecondaryButtonStyle: ButtonStyle {
    var height = Theme.buttonHeight

    func makeBody(configuration: Configuration) -> some View {
        PhasedLabel(
            configuration: configuration,
            weight: .medium,
            height: height,
            text: { $0 == .disabled ? Theme.textDisabled : Theme.textPrimary },
            fill: { phase in
                switch phase {
                case .normal: Theme.controlHover
                case .hovered: Theme.activeTab
                case .pressed, .disabled: Theme.control
                }
            })
    }
}

/// A secondary action with an outline, next to a filled one (*Retry*).
struct OutlinedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PhasedLabel(
            configuration: configuration,
            weight: .medium,
            height: Theme.buttonHeight,
            text: { $0 == .disabled ? Theme.textDisabled : Theme.textPrimary },
            fill: { phase in
                switch phase {
                case .normal, .disabled: .clear
                case .hovered: Theme.rowHover
                case .pressed: Theme.control
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                .strokeBorder(Theme.lineStrong, lineWidth: 1)
        )
    }
}

/// Danger: red text, never a red fill (*Disconnect*).
struct DangerButtonStyle: ButtonStyle {
    var height = Theme.buttonHeight

    func makeBody(configuration: Configuration) -> some View {
        PhasedLabel(
            configuration: configuration,
            weight: .medium,
            height: height,
            text: { $0 == .disabled ? Theme.textDisabled : Theme.redText },
            fill: { phase in
                switch phase {
                case .normal, .disabled: .clear
                case .hovered: Theme.redText.opacity(0.16)
                case .pressed: Theme.redText.opacity(0.28)
                }
            })
    }
}

/// Icon-only, 28 × 28 (*close*). Give the button an accessibility label.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconLabel(configuration: configuration)
    }

    private struct IconLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovered = false

        private var fill: Color {
            if configuration.isPressed { return Theme.activeTab }
            return hovered && isEnabled ? Theme.controlHover : Theme.control
        }

        var body: some View {
            configuration.label
                .foregroundStyle(isEnabled ? (hovered ? Theme.textPrimary : Theme.textSecondary) : Theme.textDisabled)
                .frame(width: Theme.buttonHeight, height: Theme.buttonHeight)
                .background(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous).fill(fill))
                .contentShape(Rectangle())
                .onHover { hovered = $0 }
        }
    }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    /// The buttons in Settings' cards are plain secondary buttons.
    static var settings: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == DangerButtonStyle {
    static var danger: DangerButtonStyle { DangerButtonStyle() }
}

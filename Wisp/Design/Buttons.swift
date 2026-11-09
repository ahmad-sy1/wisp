import SwiftUI

/// The button variants of board 0.2. Hover goes one step up the grey ladder, pressing
/// one step back; a disabled button loses its colour.
private enum ButtonPhase {
    case normal, hovered, pressed, disabled
}

private struct PhasedLabel: View {
    let configuration: ButtonStyleConfiguration
    let weight: Font.Weight
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
            .frame(height: Theme.buttonHeight)
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
    func makeBody(configuration: Configuration) -> some View {
        AccentLabel(configuration: configuration)
    }

    private struct AccentLabel: View {
        let configuration: ButtonStyleConfiguration
        @ObservedObject private var prefs = Preferences.shared

        var body: some View {
            PhasedLabel(
                configuration: configuration,
                weight: .semibold,
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
    func makeBody(configuration: Configuration) -> some View {
        PhasedLabel(
            configuration: configuration,
            weight: .medium,
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

/// Danger: red text, never a red fill (*Disconnect*).
struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PhasedLabel(
            configuration: configuration,
            weight: .medium,
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

extension ButtonStyle where Self == SecondaryButtonStyle {
    /// The buttons in Settings' cards are plain secondary buttons.
    static var settings: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == DangerButtonStyle {
    static var danger: DangerButtonStyle { DangerButtonStyle() }
}

import SwiftUI

/// What a segment shows: a word, or an icon that explains itself in a tooltip.
enum SegmentLabel {
    case text(String)
    case symbol(String, help: String)
}

/// Two to four fixed choices inside one track (board 0.2): *All / Unread*, *25 / 50 / 90 min*.
struct SegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let values: [Value]
    let label: (Value) -> SegmentLabel
    var height: CGFloat = 30
    var fontSize: CGFloat = 13
    /// Equal widths for short labels; `nil` lets each segment fit its text.
    var segmentWidth: CGFloat?
    /// Stretch the segments to fill the width they are given.
    var fillsWidth = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(values, id: \.self) { value in
                Segment(
                    label: label(value),
                    selected: value == selection,
                    height: height - 4,
                    fontSize: fontSize,
                    width: segmentWidth,
                    fillsWidth: fillsWidth
                ) {
                    selection = value
                }
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                .fill(Theme.control)
        )
    }

    private struct Segment: View {
        let label: SegmentLabel
        let selected: Bool
        let height: CGFloat
        let fontSize: CGFloat
        let width: CGFloat?
        let fillsWidth: Bool
        let action: () -> Void

        @Environment(\.isEnabled) private var isEnabled
        @State private var hovered = false

        private var foreground: Color {
            if !isEnabled { return Theme.textDisabled }
            return selected || hovered ? Theme.textPrimary : Theme.textSecondary
        }

        private var fill: Color {
            guard selected else { return .clear }
            return isEnabled ? Theme.trackOff : Theme.activeTab
        }

        var body: some View {
            Button(action: action) {
                content
                    .foregroundStyle(foreground)
                    .frame(width: width, height: height)
                    .frame(maxWidth: fillsWidth ? .infinity : nil)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.smallCorner, style: .continuous)
                            .fill(fill)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(SegmentButtonStyle())
            .focusable(false)
            .onHover { hovered = $0 }
            .modifier(SegmentHelp(label: label))
        }

        @ViewBuilder private var content: some View {
            switch label {
            case .text(let title):
                Text(title)
                    .font(.system(size: fontSize, weight: selected ? .semibold : .regular))
                    .fixedSize()
                    .padding(.horizontal, width == nil && !fillsWidth ? 8 : 0)
            case .symbol(let name, _):
                Image(systemName: name).font(.system(size: fontSize))
            }
        }
    }
}

extension SegmentedControl {
    /// A control whose segments are all words.
    init(
        selection: Binding<Value>,
        values: [Value],
        title: @escaping (Value) -> String,
        height: CGFloat = 30,
        fontSize: CGFloat = 13,
        segmentWidth: CGFloat? = nil,
        fillsWidth: Bool = false
    ) {
        self.init(
            selection: selection,
            values: values,
            label: { .text(title($0)) },
            height: height,
            fontSize: fontSize,
            segmentWidth: segmentWidth,
            fillsWidth: fillsWidth)
    }
}

/// `.plain` would dim a disabled segment a second time; the segment draws that itself.
private struct SegmentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private struct SegmentHelp: ViewModifier {
    let label: SegmentLabel

    func body(content: Content) -> some View {
        if case .symbol(_, let help) = label {
            content.help(help).accessibilityLabel(help)
        } else {
            content
        }
    }
}

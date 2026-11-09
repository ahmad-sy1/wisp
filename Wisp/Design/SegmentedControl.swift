import SwiftUI

/// Two to four fixed choices inside one track (board 0.2): *All / Unread*, *25 / 50 / 90 min*.
struct SegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let values: [Value]
    let title: (Value) -> String
    var height: CGFloat = 30
    var fontSize: CGFloat = 13
    /// Equal widths for short labels; `nil` lets each segment fit its text.
    var segmentWidth: CGFloat?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(values, id: \.self) { value in
                Segment(
                    title: title(value),
                    selected: value == selection,
                    height: height - 4,
                    fontSize: fontSize,
                    width: segmentWidth
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
        let title: String
        let selected: Bool
        let height: CGFloat
        let fontSize: CGFloat
        let width: CGFloat?
        let action: () -> Void

        @State private var hovered = false

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.system(size: fontSize, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected || hovered ? Theme.textPrimary : Theme.textSecondary)
                    .fixedSize()
                    .padding(.horizontal, width == nil ? 8 : 0)
                    .frame(width: width, height: height)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.smallCorner, style: .continuous)
                            .fill(selected ? Theme.trackOff : .clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
        }
    }
}

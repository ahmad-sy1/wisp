import AppKit
import SwiftUI

/// Board 11.3: every integration's tab has the same build. A 28 pt header (tile, name,
/// status, a link to the service) above a 572 × 114 area holding up to three metrics, a
/// list of up to three rows, or a state card.
struct IntegrationTab<Content: View>: View {
    let info: IntegrationInfo
    let status: IntegrationTabStatus
    let linkTitle: String
    let link: URL
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 8) {
            IntegrationTabHeader(info: info, status: status, linkTitle: linkTitle, link: link)
                .frame(height: Theme.tabBarHeight)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The dot and the words after the name.
struct IntegrationTabStatus: Equatable {
    enum Tone { case ok, idle, problem }

    let tone: Tone
    let text: String

    /// "Synced 5 min ago", kept current while the panel is open.
    static func synced(_ date: Date?, now: Date) -> IntegrationTabStatus {
        guard let date else { return IntegrationTabStatus(tone: .idle, text: String(localized: "Connecting…")) }
        let minutes = Int(now.timeIntervalSince(date) / 60)
        let text: String =
            switch minutes {
            case ..<1: String(localized: "Synced just now")
            case ..<60: String(localized: "Synced \(minutes) min ago")
            default: String(localized: "Synced at \(date.formatted(date: .omitted, time: .shortened))")
            }
        return IntegrationTabStatus(tone: .ok, text: text)
    }
}

private struct IntegrationTabHeader: View {
    let info: IntegrationInfo
    let status: IntegrationTabStatus
    let linkTitle: String
    let link: URL
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            ServiceIcon(letters: info.letters, color: Color(hex: info.tint), size: .tab)
            Text(verbatim: info.name)
                .font(.system(size: 14, weight: .semibold))
            HStack(spacing: 5) {
                Circle().fill(dot).frame(width: 6, height: 6)
                Text(status.text)
                    .font(.system(size: 12))
                    .foregroundStyle(status.tone == .problem ? Theme.redText : Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                NSWorkspace.shared.open(link)
            } label: {
                HStack(spacing: 3) {
                    Text(linkTitle)
                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 12))
                .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
        .padding(.horizontal, 2)
    }

    private var dot: Color {
        switch status.tone {
        case .ok: Theme.ok
        case .idle: Theme.textFaint
        case .problem: Theme.badge
        }
    }
}

/// One of up to three equal tiles: a label, a big value, a small graphic and a line of context.
struct IntegrationMetric<Graphic: View>: View {
    let label: String
    let value: String
    let footer: String
    @ViewBuilder var graphic: Graphic

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                Text(label.uppercased())
                    .font(.system(size: 10.5, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(Theme.textSecondary)
                Text(verbatim: value)
                    .font(.system(size: 21, weight: .semibold))
                    .monospacedDigit()
                    .padding(.top, 2)
                Spacer(minLength: 4)
                graphic.frame(height: 14)
                Spacer(minLength: 4)
                Text(footer)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// A thin bar of coloured parts that fill `total` (sleep stages, strain on its scale).
struct SegmentBar: View {
    struct Part: Identifiable {
        let id = UUID()
        let value: Double
        let color: Color
    }

    let parts: [Part]
    var total: Double?

    var body: some View {
        GeometryReader { geometry in
            let sum = total ?? parts.reduce(0) { $0 + $1.value }
            let gaps = CGFloat(max(parts.count - 1, 0)) * 2
            let width = max(geometry.size.width - (total == nil ? gaps : 0), 0)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.control)
                HStack(spacing: total == nil ? 2 : 0) {
                    ForEach(parts) { part in
                        Capsule()
                            .fill(part.color)
                            .frame(width: sum > 0 ? width * min(part.value / sum, 1) : 0)
                    }
                }
            }
        }
        .frame(height: 5)
    }
}

/// When there is nothing to show: no data yet, or the connection is lost.
struct IntegrationStateCard<Actions: View>: View {
    let symbol: String
    var isProblem = false
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        Card {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: Theme.iconCorner, style: .continuous)
                    .fill(isProblem ? Theme.badge.opacity(0.16) : Theme.control)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: symbol)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(isProblem ? Theme.redText : Theme.textSecondary)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) { actions }
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

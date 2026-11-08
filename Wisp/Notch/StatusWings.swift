import AppKit
import SwiftUI

/// A status on the closed notch (design page 1): what matters left and right of the camera,
/// and nothing when nothing matters. Colour follows urgency.
struct StatusWings: Equatable {
    enum Icon: Equatable {
        case symbol(String, Color)
        /// A run is going.
        case spinner
        /// A symbol with a small dot next to it (a review request).
        case symbolDot(String, Color)
    }

    var icon: Icon
    var left: String
    var leftColor: Color = Theme.textPrimary
    var right: String
    var rightColor: Color = Theme.textSecondary
    /// An optional symbol before the right text (the rain cloud).
    var rightSymbol: String?
    /// Urgent statuses go above the music wings; others wait until the music stops.
    var urgent: Bool
    /// The tab a click on the notch opens.
    var tab: WispTab

    /// Free room between the text and the camera.
    private static let cameraGap: CGFloat = 8
    /// The most a wing may take. Keep statuses to a word or a number; the tab has the details.
    private static let maxWingWidth: CGFloat = 96

    /// Both wings get the same width because the window is centred on the camera, so the
    /// longest text sets both.
    var wingWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let leftText = (left as NSString).size(withAttributes: [.font: font]).width
        let rightText = (right as NSString).size(withAttributes: [.font: font]).width
        let iconWidth: CGFloat = if case .symbolDot = icon { 30 } else { 20 }
        let rightIcon: CGFloat = rightSymbol == nil ? 0 : 18
        return min(Self.maxWingWidth, max(leftText + iconWidth, rightText + rightIcon) + Self.cameraGap).rounded(.up)
    }
}

struct StatusWingsView: View {
    let status: StatusWings
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                icon
                Text(verbatim: status.left)
                    .foregroundStyle(status.leftColor)
            }
            .frame(width: status.wingWidth, alignment: .leading)
            .padding(.leading, 12)
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                if let symbol = status.rightSymbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(status.rightColor)
                }
                Text(verbatim: status.right)
                    .foregroundStyle(status.rightColor)
            }
            .frame(width: status.wingWidth, alignment: .trailing)
            .padding(.trailing, 12)
        }
        .font(.system(size: 12, weight: .semibold))
        .monospacedDigit()
        .lineLimit(1)
        .frame(height: height)
    }

    @ViewBuilder
    private var icon: some View {
        switch status.icon {
        case .symbol(let name, let color):
            Image.wisp(name)
                .renderingMode(.template)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
        case .spinner:
            RunSpinner(size: 12)
        case .symbolDot(let name, let color):
            Image.wisp(name)
                .renderingMode(.template)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
            Circle().fill(color).frame(width: 6, height: 6)
        }
    }
}

/// A quarter of a ring that turns. Ten steps a second, so a running job on the closed notch
/// costs next to nothing; it only exists while a run is going.
struct RunSpinner: View {
    let size: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let step = (context.date.timeIntervalSinceReferenceDate * 10).rounded(.down)
            ZStack {
                Circle().stroke(Theme.textSecondary.opacity(0.3), lineWidth: 1.75)
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(Theme.textPrimary, style: StrokeStyle(lineWidth: 1.75, lineCap: .round))
                    .rotationEffect(.degrees(step.truncatingRemainder(dividingBy: 12) * 30))
            }
            .frame(width: size, height: size)
        }
        .accessibilityLabel(Text("Running"))
    }
}

extension StatusWings {
    /// The radar's indicator as wings (design page 1). Only a run going waits behind music.
    init?(_ compact: RadarCompact) {
        switch compact {
        case .none:
            return nil
        case .running(let completed, let total):
            self.init(
                icon: .spinner, left: "CI", right: "\(completed)/\(total)",
                urgent: false, tab: .github)
        case .failed(let pull):
            self.init(
                icon: .symbol("xmark.circle", Theme.badge), left: "CI", leftColor: Theme.badge,
                right: "#\(pull.number)", urgent: true, tab: .github)
        case .reviewRequested(_, let count):
            let symbol = WispTab.github.symbol
            if count == 1 {
                self.init(
                    icon: .symbolDot(symbol, Theme.info), left: "", right: String(localized: "Review"),
                    rightColor: Theme.textPrimary, urgent: true, tab: .github)
            } else {
                self.init(
                    icon: .symbol(symbol, Theme.info), left: "\(count)", leftColor: Theme.info,
                    right: String(localized: "Reviews"), rightColor: Theme.textPrimary,
                    urgent: true, tab: .github)
            }
        case .newActivity(let pull, let count):
            self.init(
                icon: .symbolDot(WispTab.github.symbol, Theme.warning), left: "#\(pull.number)",
                right: "\(count)", rightColor: Theme.textPrimary, rightSymbol: "text.bubble", urgent: true, tab: .github)
        }
    }
}

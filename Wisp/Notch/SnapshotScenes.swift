#if DEBUG
    import SwiftUI

    /// Fixed states of the closed notch for `scripts/snapshots.sh`: `-snapshotScene ci-failed`.
    /// Made-up data only and no live sources (mail, music, GitHub, Claude Code), so a snapshot
    /// looks the same on every run and a change in it is a change in the code.
    @MainActor
    enum SnapshotScene: String, CaseIterable {
        case empty
        case emptyHover = "empty-hover"
        case ciFailed = "ci-failed"
        case ciFailedHover = "ci-failed-hover"
        case review
        case reviews
        case comments
        case departure
        case departureDelay = "departure-delay"
        case departureRain = "departure-rain"
        case mail

        /// The scene asked for at launch, if any.
        static var requested: SnapshotScene? {
            UserDefaults.standard.string(forKey: "snapshotScene").flatMap(SnapshotScene.init(rawValue:))
        }

        func apply(to notch: NotchController) {
            switch self {
            case .empty, .emptyHover:
                break
            case .ciFailed, .ciFailedHover:
                notch.setStatus(StatusWings(.failed(Self.pull)))
            case .review:
                notch.setStatus(StatusWings(.reviewRequested(Self.pull, count: 1)))
            case .reviews:
                notch.setStatus(StatusWings(.reviewRequested(Self.pull, count: 3)))
            case .comments:
                notch.setStatus(StatusWings(.newActivity(Self.pull, count: 2)))
            case .departure:
                notch.setStatus(Self.trip(.transit, left: "12 min", right: "08:42"))
            case .departureDelay:
                notch.setStatus(
                    Self.trip(.transit, left: "4 min", leftColor: Theme.warning, right: "+4 min", rightColor: Theme.warning))
            case .departureRain:
                notch.setStatus(
                    Self.trip(.bike, left: "9 min", right: "15 min", rightColor: Theme.rain, rightSymbol: "cloud.rain"))
            case .mail:
                notch.model.unreadCount = 3
                notch.setMailWings(true)
            }
            if self == .emptyHover || self == .ciFailedHover { notch.model.hovering = true }
        }

        private static let pull = PullRequest(
            repository: "demo/wisp", number: 63, title: "Snapshot", url: URL(string: "https://example.com/pull/63")!,
            isDraft: false, updatedAt: Date(timeIntervalSinceReferenceDate: 0))

        private static func trip(
            _ mode: TravelMode, left: String, leftColor: Color = Theme.textPrimary, right: String,
            rightColor: Color = Theme.textSecondary, rightSymbol: String? = nil
        ) -> StatusWings {
            StatusWings(
                icon: .symbol(mode.symbol, leftColor), left: left, leftColor: leftColor, right: right,
                rightColor: rightColor, rightSymbol: rightSymbol, urgent: true, tab: .departure)
        }
    }
#endif

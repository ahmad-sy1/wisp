import AppKit
import SwiftUI

/// GitHub (design page 3): your pull requests or the requested reviews on the left, the
/// contribution graph on the right.
struct GitHubTab: View {
    @ObservedObject var store: GitHubStore
    var openSettings: () -> Void = {}

    var body: some View {
        Group {
            if store.isConnected || !store.snapshot.mine.isEmpty {
                HStack(spacing: 10) {
                    Card { PullList(store: store) }
                        .frame(width: 306)
                    Card { ContributionCard(stats: store.stats) }
                }
            } else {
                Card { notConnected.frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
        }
        .onAppear { store.setTabVisible(true) }
        .onDisappear { store.setTabVisible(false) }
    }

    private var notConnected: some View {
        VStack(spacing: 10) {
            Image.wisp(WispTab.github.symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.textSecondary)
            switch store.status {
            case .connecting:
                Text("Connecting…")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            case .failed(let message):
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                connect
            default:
                Text("See your pull requests and their checks here.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                connect
            }
        }
    }

    private var connect: some View {
        Button("Connect GitHub") {
            SettingsNavigation.shared.page = .github
            openSettings()
        }
        .buttonStyle(SecondaryButtonStyle())
    }
}

// MARK: - Pull requests

private struct PullList: View {
    @ObservedObject var store: GitHubStore
    @State private var showing: Section = .mine

    private enum Section { case mine, reviews }

    private var pulls: [PullRequest] {
        showing == .mine ? store.snapshot.mine : store.snapshot.reviews
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                segment(.mine, String(localized: "My PRs · \(store.snapshot.mine.count)"))
                segment(.reviews, String(localized: "Reviews · \(store.snapshot.reviews.count)"))
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous).fill(Theme.control))
            .fixedSize()

            if pulls.isEmpty {
                Text(showing == .mine ? "No open pull requests" : "Nothing to review")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PanelScroll {
                    VStack(spacing: 0) {
                        ForEach(pulls) { pull in
                            PullRow(pull: pull, unseen: store.seen.unseenActivity[pull.id] ?? 0, isReview: showing == .reviews)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func segment(_ section: Section, _ title: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { showing = section }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: showing == section ? .semibold : .regular))
                .foregroundStyle(showing == section ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: Theme.smallCorner, style: .continuous)
                        .fill(showing == section ? Theme.activeTab : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

private struct PullRow: View {
    let pull: PullRequest
    let unseen: Int
    let isReview: Bool
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                NSWorkspace.shared.open(pull.url)
            } label: {
                HStack(spacing: 8) {
                    indicator.frame(width: 12)
                    Text(pull.title)
                        .font(.system(size: 12.5))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(verbatim: "\(pull.repositoryName) #\(pull.number)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                    if !isReview {
                        Text(statusText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(statusColor)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .frame(height: 25)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(pull.url.absoluteString)

            // A failure says what failed, and takes you there.
            if !isReview, pull.checks.status == .failed, let job = pull.checks.failedJobs.first {
                Button {
                    NSWorkspace.shared.open(job.url ?? pull.url)
                } label: {
                    HStack(spacing: 4) {
                        Text(verbatim: job.name)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.badge)
                    .padding(.leading, 20)
                    .padding(.bottom, 3)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .focusable(false)
    }

    @ViewBuilder
    private var indicator: some View {
        if isReview {
            Circle().fill(Theme.info).frame(width: 7, height: 7)
        } else if unseen > 0 {
            Circle().fill(Theme.warning).frame(width: 7, height: 7)
        } else {
            switch pull.checks.status {
            case .running: RunSpinner(size: 11)
            case .failed: Circle().fill(Theme.badge).frame(width: 7, height: 7)
            case .passed: Circle().fill(Theme.ok).frame(width: 7, height: 7)
            case .none: Circle().fill(Theme.textSecondary.opacity(0.5)).frame(width: 7, height: 7)
            }
        }
    }

    private var statusText: String {
        if unseen > 0 { return unseen == 1 ? String(localized: "1 comment") : String(localized: "\(unseen) comments") }
        switch pull.checks.status {
        case .running: return "\(pull.checks.completed)/\(pull.checks.total)"
        case .failed: return String(localized: "failed")
        case .passed: return String(localized: "done")
        case .none: return pull.isDraft ? String(localized: "draft") : ""
        }
    }

    private var statusColor: Color {
        if unseen > 0 { return Theme.warning }
        switch pull.checks.status {
        case .running, .none: return Theme.textSecondary
        case .failed: return Theme.badge
        case .passed: return Theme.ok
        }
    }
}

// MARK: - Contributions

private struct ContributionCard: View {
    let stats: ContributionStats?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("CONTRIBUTIONS")
                    .font(.system(size: 10.5, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("16 weeks")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            ContributionGrid(weeks: stats?.weeks ?? [])
            HStack(alignment: .top) {
                number(stats?.streak, String(localized: "day streak"))
                Spacer()
                number(stats?.commitsThisWeek, String(localized: "commits/week"))
                Spacer()
                number(stats?.mergedThisWeek, String(localized: "merged"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func number(_ value: Int?, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: value.map(String.init) ?? "–")
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }
}

/// 16 weeks of 7 days, drawn in one pass.
private struct ContributionGrid: View {
    let weeks: [[Int]]
    private static let columns = 16

    var body: some View {
        Canvas { context, size in
            let gap: CGFloat = 2.5
            let side = min(
                (size.width - gap * CGFloat(Self.columns - 1)) / CGFloat(Self.columns),
                (size.height - gap * 6) / 7)
            let across = (size.width - side) / CGFloat(Self.columns - 1)
            let shown = Array(weeks.suffix(Self.columns))
            for column in 0..<Self.columns {
                // Fewer weeks than columns (no data yet): empty cells on the left.
                let week = column >= Self.columns - shown.count ? shown[column - (Self.columns - shown.count)] : []
                for row in 0..<7 {
                    let level = row < week.count ? week[row] : 0
                    let rect = CGRect(x: CGFloat(column) * across, y: CGFloat(row) * (side + gap), width: side, height: side)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(Self.color(level)))
                }
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    private static func color(_ level: Int) -> Color {
        switch level {
        case 1: Theme.ok.opacity(0.28)
        case 2: Theme.ok.opacity(0.5)
        case 3: Theme.ok.opacity(0.75)
        case 4: Theme.ok
        default: Theme.control
        }
    }
}

/// A scroll view, except in `-snapshot` runs: `cacheDisplay` leaves scroll views empty.
struct PanelScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        #if DEBUG
            if UserDefaults.standard.string(forKey: "snapshot") != nil {
                content.frame(minHeight: 0, maxHeight: .infinity, alignment: .top).clipped()
            } else {
                ScrollView { content }.scrollIndicators(.never)
            }
        #else
            ScrollView { content }.scrollIndicators(.never)
        #endif
    }
}

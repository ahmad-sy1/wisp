import AppKit
import SwiftUI

/// Your next event on Home. Small: one line. Medium: its time. Large: the next few.
struct NextEventItem: View {
    let place: HomePlace
    @ObservedObject private var agenda = AgendaStore.shared

    private func upcoming(at now: Date) -> [AgendaEvent] {
        agenda.events.filter { !$0.isAllDay && $0.end > now }
    }

    private func color(_ event: AgendaEvent) -> Color { event.isShift ? Theme.warning : event.color }

    var body: some View {
        Card {
            // Moves on to the next event by itself; only runs while Home is open.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                content(upcoming(at: context.date))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func content(_ events: [AgendaEvent]) -> some View {
        if let next = events.first {
            switch place {
            case .small:
                VStack(alignment: .leading, spacing: 4) {
                    label(color(next))
                    Text("\(next.title) at \(next.start.clockTime)")
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                }
            case .medium:
                VStack(alignment: .leading, spacing: 6) {
                    label(color(next))
                    Text(next.title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                    Text(verbatim: "\(next.start.clockTime) – \(next.end.clockTime)")
                        .font(.system(size: 12.5))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .large:
                VStack(alignment: .leading, spacing: 9) {
                    label(color(next))
                    ForEach(events.prefix(3)) { event in
                        HStack(spacing: 10) {
                            Text(verbatim: event.start.clockTime)
                                .font(.system(size: 13))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                            RoundedRectangle(cornerRadius: 1.5).fill(color(event)).frame(width: 3, height: 16)
                            Text(event.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                label(Theme.textSecondary.opacity(0.5))
                Text("Nothing planned")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func label(_ dot: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text("Next event").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
        }
    }
}

/// GitHub on Home (board 11.2). Small: the most important pull request. Medium: with its
/// checks and review. Large: three of them.
struct GitHubItem: View {
    let place: HomePlace
    @ObservedObject private var github = GitHubStore.shared

    private var snapshot: RadarSnapshot { github.snapshot }

    private func isReview(_ pull: PullRequest) -> Bool {
        snapshot.reviews.contains { $0.id == pull.id }
    }

    var body: some View {
        Card {
            Group {
                if !github.isConnected {
                    empty(String(localized: "Not connected"))
                } else if let pull = snapshot.mostImportant {
                    switch place {
                    case .small: small(pull)
                    case .medium: medium(pull)
                    case .large: large
                    }
                } else {
                    empty(String(localized: "No open pull requests"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var icon: some View { ServiceIcon(letters: "GH", color: Theme.textPrimary) }

    private func empty(_ text: String) -> some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "GitHub").font(.system(size: 13.5, weight: .semibold))
                Text(text).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
        }
    }

    private func checkText(_ checks: CheckSummary) -> String {
        switch checks.status {
        case .passed: String(localized: "Checks passing")
        case .failed: String(localized: "Checks failed")
        case .running: String(localized: "Checks running · \(checks.completed)/\(checks.total)")
        case .none: String(localized: "No checks")
        }
    }

    private func checkIcon(_ status: CheckStatus) -> some View {
        Group {
            switch status {
            case .passed: Image(systemName: "checkmark").foregroundStyle(Theme.ok)
            case .failed: Image(systemName: "xmark").foregroundStyle(Theme.redText)
            case .running: Image(systemName: "clock").foregroundStyle(Theme.warning)
            case .none: Image(systemName: "minus").foregroundStyle(Theme.textSecondary)
            }
        }
        .font(.system(size: 10.5, weight: .semibold))
        .frame(width: 13)
    }

    private func open(_ pull: PullRequest) { NSWorkspace.shared.open(pull.url) }

    private func small(_ pull: PullRequest) -> some View {
        HStack(spacing: 11) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text("PR #\(pull.number) · \(pull.title)").font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    checkIcon(pull.checks.status)
                    Text(checkText(pull.checks)).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if isReview(pull) { reviewPill }
        }
        .contentShape(Rectangle())
        .onTapGesture { open(pull) }
    }

    private var reviewPill: some View {
        Text("Review")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.info)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Capsule().fill(Theme.info.opacity(0.18)))
    }

    private var header: some View {
        HStack(spacing: 8) {
            ServiceIcon(letters: "GH", color: Theme.textPrimary, size: .small)
            Text(verbatim: "GitHub").font(.system(size: 13, weight: .semibold))
            Text("\(snapshot.mine.count) open").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
        }
    }

    private func medium(_ pull: PullRequest) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            Spacer(minLength: 0)
            Text("#\(pull.number) \(pull.title)").font(.system(size: 14, weight: .semibold)).lineLimit(2)
            HStack(spacing: 4) {
                checkIcon(pull.checks.status)
                Text(checkText(pull.checks)).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            if isReview(pull) {
                HStack(spacing: 6) {
                    Circle().fill(Theme.info).frame(width: 6, height: 6).frame(width: 13)
                    Text("Review requested").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { open(pull) }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ForEach(Array((snapshot.reviews + snapshot.mine).prefix(3))) { pull in
                HStack(spacing: 8) {
                    checkIcon(pull.checks.status)
                    Text("#\(pull.number) \(pull.title)").font(.system(size: 13)).lineLimit(1)
                    Spacer(minLength: 8)
                    if isReview(pull) {
                        Text("Review requested").font(.system(size: 12)).foregroundStyle(Theme.info).lineLimit(1)
                    } else {
                        Text(checkText(pull.checks)).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { open(pull) }
            }
            Spacer(minLength: 0)
        }
    }
}

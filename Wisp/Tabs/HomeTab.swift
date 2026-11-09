import SwiftUI

/// Home: one to four things, chosen in Settings → Notch (boards 10.1.3, 11.1). A permission
/// request takes the whole width.
struct HomeTab: View {
    @ObservedObject var sessions: ClaudeSessions
    @ObservedObject private var prefs = Preferences.shared

    private static let gap: CGFloat = 10

    var body: some View {
        if let approval = sessions.approval {
            ApprovalCard(approval: approval) { sessions.answer($0) }
        } else {
            grid(prefs.homeLayout ?? .standard)
        }
    }

    @ViewBuilder
    private func grid(_ layout: HomeLayout) -> some View {
        let items = layout.items
        switch items.count {
        case 1:
            cell(items[0], .large)
        case 2:
            HStack(spacing: Self.gap) {
                cell(items[0], .medium)
                cell(items[1], .medium)
            }
        case 3:
            HStack(spacing: Self.gap) {
                cell(items[0], .medium)
                VStack(spacing: Self.gap) {
                    cell(items[1], .small)
                    cell(items[2], .small)
                }
            }
        default:
            VStack(spacing: Self.gap) {
                HStack(spacing: Self.gap) {
                    cell(items[0], .small)
                    cell(items[1], .small)
                }
                HStack(spacing: Self.gap) {
                    cell(items[2], .small)
                    cell(items[3], .small)
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ item: HomeItem, _ place: HomePlace) -> some View {
        switch item {
        case .inProgress:
            if place == .small {
                NowSmallCard(session: sessions.primary)
            } else {
                NowCard(session: sessions.primary)
            }
        case .nextEvent: NextEventItem(place: place)
        case .github: GitHubItem(place: place)
        case .music: HomeMusicItem(place: place)
        }
    }
}

// MARK: - Now

private struct NowCard: View {
    let session: ClaudeSession?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    IconTile(symbol: "chevron.left.forwardslash.chevron.right")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("IN PROGRESS")
                            .font(.system(size: 10.5, weight: .medium))
                            .tracking(0.6)
                            .foregroundStyle(Theme.textSecondary)
                        Text(session?.host.name ?? String(localized: "No session"))
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if let session {
                    Text([session.project, session.branch].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    StatusLine(session: session)
                        .padding(.top, 3)
                    Spacer(minLength: 8)
                    Button("Open project") { session.host.open(project: session.cwd) }
                        .buttonStyle(AccentButtonStyle())
                } else {
                    Text("Start Claude Code in IntelliJ or a terminal to see it here.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// The small version: the app and how it's going, with a way to open the project.
private struct NowSmallCard: View {
    let session: ClaudeSession?

    var body: some View {
        Card {
            HStack(spacing: 12) {
                IconTile(symbol: "chevron.left.forwardslash.chevron.right")
                VStack(alignment: .leading, spacing: 3) {
                    Text(session?.host.name ?? String(localized: "No session"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                    if let session {
                        StatusLine(session: session)
                    } else {
                        Text("Start Claude Code to see it here.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if let session {
                    Button {
                        session.host.open(project: session.cwd)
                    } label: {
                        Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(IconButtonStyle())
                    .focusable(false)
                    .accessibilityLabel("Open project")
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

private struct StatusLine: View {
    let session: ClaudeSession

    var body: some View {
        // Refreshes once a minute, and only while the panel is open.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(text(now: context.date))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var color: Color {
        switch session.state {
        case .working: Preferences.shared.accent.color
        case .waiting, .question: Theme.warning
        case .failed: Theme.badge
        case .idle, .finished: Theme.ok
        }
    }

    private func text(now: Date) -> String {
        switch session.state {
        case .working: return session.tool.map { String(localized: "Working · \($0)") } ?? String(localized: "Working…")
        case .waiting: return String(localized: "Waiting for permission")
        case .question: return String(localized: "Has a question for you")
        case .failed: return String(localized: "Stopped with an error")
        case .finished: return String(localized: "Done · \(Self.duration(now.timeIntervalSince(session.startedAt))) focused")
        case .idle: return String(localized: "Connected · \(Self.duration(now.timeIntervalSince(session.startedAt))) focused")
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds) / 60)
        return minutes < 60 ? String(localized: "\(minutes)m") : String(localized: "\(minutes / 60)h \(minutes % 60)m")
    }
}

// MARK: - Permission request

private struct ApprovalCard: View {
    let approval: PendingApproval
    let answer: (String) -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    IconTile(symbol: "hand.raised", tint: Theme.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PERMISSION NEEDED")
                            .font(.system(size: 10.5, weight: .medium))
                            .tracking(0.6)
                            .foregroundStyle(Theme.warning)
                        Text("\(approval.project) wants to use \(approval.tool)")
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                    }
                }

                Text(approval.summary ?? approval.tool)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous).fill(Theme.control))

                HStack(spacing: 8) {
                    Spacer()
                    // Not focusable: an answer takes a click, never a key (the panel can be
                    // key since the shortcut, and Space presses a focused button).
                    Button("In terminal") { answer("ask") }
                        .buttonStyle(SecondaryButtonStyle())
                        .focusable(false)
                    Button("Deny") { answer("deny") }
                        .buttonStyle(SecondaryButtonStyle())
                        .focusable(false)
                    Button("Allow") { answer("allow") }
                        .buttonStyle(AccentButtonStyle())
                        .focusable(false)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Shared pieces

struct IconTile: View {
    let symbol: String
    var tint: Color = Theme.textPrimary

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.iconCorner, style: .continuous)
            .fill(Theme.control)
            .frame(width: 40, height: 40)
            .overlay(Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(tint))
    }
}

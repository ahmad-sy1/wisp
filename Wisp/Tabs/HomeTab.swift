import SwiftUI

/// Home: "Nu bezig" (the current Claude Code session) on the left, four compact
/// integration tiles on the right. A permission request takes the whole width.
struct HomeTab: View {
    @ObservedObject var sessions: ClaudeSessions

    var body: some View {
        if let approval = sessions.approval {
            ApprovalCard(approval: approval) { sessions.answer($0) }
        } else {
            HStack(spacing: 10) {
                NowCard(session: sessions.primary)
                    .frame(width: 296)
                IntegrationGrid()
            }
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
        case .working:           Preferences.shared.accent.color
        case .waiting, .question: Theme.warning
        case .failed:            Theme.badge
        case .idle, .finished:   Theme.ok
        }
    }

    private func text(now: Date) -> String {
        switch session.state {
        case .working:  return session.tool.map { String(localized: "Working · \($0)") } ?? String(localized: "Working…")
        case .waiting:  return String(localized: "Waiting for permission")
        case .question: return String(localized: "Has a question for you")
        case .failed:   return String(localized: "Stopped with an error")
        case .finished: return String(localized: "Done · \(Self.duration(now.timeIntervalSince(session.startedAt))) focused")
        case .idle:     return String(localized: "Connected · \(Self.duration(now.timeIntervalSince(session.startedAt))) focused")
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
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.control))

                HStack(spacing: 8) {
                    Spacer()
                    Button("In terminal") { answer("ask") }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Deny") { answer("deny") }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Allow") { answer("allow") }
                        .buttonStyle(AccentButtonStyle())
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Integration tiles

private struct IntegrationGrid: View {
    @ObservedObject var player: NowPlaying = .shared

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            // GitHub, WHOOP and Notion get live data once those integrations move over.
            GridRow { tile("GitHub"); tile("WHOOP") }
            GridRow { musicTile; tile("Notion") }
        }
    }

    private var musicTile: some View {
        let track = player.track
        let value = track.map { [$0.title, $0.artist].filter { !$0.isEmpty }.joined(separator: " · ") }
        return tile(String(localized: "Music"), value: value ?? String(localized: "Nothing is playing"),
                    dot: track?.isPlaying == true ? Theme.ok : nil,
                    dim: track == nil)
    }

    private func tile(_ name: String, value: String = String(localized: "Not connected"),
                      dot: Color? = nil, dim: Bool = true) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(dot ?? Theme.textSecondary.opacity(0.5)).frame(width: 7, height: 7)
                    Text(name).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(dim ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Shared pieces

struct IconTile: View {
    let symbol: String
    var tint: Color = Theme.textPrimary

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.control)
            .frame(width: 40, height: 40)
            .overlay(Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(tint))
    }
}

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AccentLabel(configuration: configuration)
    }

    private struct AccentLabel: View {
        let configuration: ButtonStyleConfiguration
        @ObservedObject private var prefs = Preferences.shared

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: Theme.buttonHeight)
                .background(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                    .fill(prefs.accent.color))
                .opacity(configuration.isPressed ? 0.75 : 1)
        }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: Theme.buttonHeight)
            .background(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                .fill(configuration.isPressed ? Theme.activeTab : Theme.control))
    }
}

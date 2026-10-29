import Foundation

struct ClaudeSession: Identifiable, Equatable {
    enum State: Equatable { case idle, working, waiting, question, finished, failed }

    let id: String
    var cwd: String
    var host: HostApp
    var branch: String?
    var state: State = .idle
    var tool: String?
    let startedAt: Date
    var lastEventAt: Date

    var project: String {
        cwd.isEmpty ? "Claude Code" : URL(fileURLWithPath: cwd).lastPathComponent
    }
}

/// A permission request waiting for a click in the notch.
struct PendingApproval: Identifiable {
    let id = UUID()
    let sessionId: String
    let project: String
    let tool: String
    let summary: String?
    let reply: HookReply
}

/// Claude Code sessions as seen through the hooks.
@MainActor
final class ClaudeSessions: ObservableObject {
    static let shared = ClaudeSessions()

    @Published private(set) var sessions: [String: ClaudeSession] = [:]
    @Published private(set) var approval: PendingApproval?

    /// Called when something needs the user (a permission request).
    var onNeedsAttention: () -> Void = {}
    /// Called once that request has been answered.
    var onAnswered: () -> Void = {}

    /// Unanswered permission requests fall back to the terminal after this long,
    /// a little before `wisp-hook` itself stops waiting.
    private let approvalTimeout: TimeInterval = 110
    private let staleAfter: TimeInterval = 3 * 3600

    /// The session the Home tab shows: the one asking for permission, otherwise the
    /// most recent IDE session, otherwise the most recent one.
    var primary: ClaudeSession? {
        if let approval, let s = sessions[approval.sessionId] { return s }
        let recent = sessions.values.sorted { $0.lastEventAt > $1.lastEventAt }
        return recent.first { $0.host.isIDE } ?? recent.first
    }

    func handle(_ event: HookEvent, reply: HookReply?) {
        let now = Date()
        pruneStale(now: now)

        if event.name == "SessionEnd" {
            sessions[event.sessionId] = nil
            if approval?.sessionId == event.sessionId { answer("ask") }
            return
        }

        var session = sessions[event.sessionId] ?? ClaudeSession(
            id: event.sessionId, cwd: event.cwd,
            host: HostApp(termProgram: event.termProgram, bundleId: event.bundleId),
            startedAt: now, lastEventAt: now)
        if !event.cwd.isEmpty { session.cwd = event.cwd }
        session.branch = GitInfo.branch(at: session.cwd)
        session.lastEventAt = now

        switch event.name {
        case "UserPromptSubmit", "PostToolUse", "PostToolUseFailure":
            session.state = .working
        case "PreToolUse":
            session.state = .working
            session.tool = event.toolName
        case "Notification":
            if let message = event.message?.lowercased() {
                if message.contains("permission") { session.state = .waiting }
                else if message.hasSuffix("?") { session.state = .question }
            }
        case "Stop":
            session.state = .finished
            session.tool = nil
        case "StopFailure":
            session.state = .failed
            session.tool = nil
        case "PermissionRequest":
            session.state = .waiting
            session.tool = event.toolName
        default:
            break
        }
        sessions[event.sessionId] = session

        if let reply { requestApproval(event, session: session, reply: reply) }
    }

    /// Answers the pending permission request. Only ever called from a click
    /// (or "ask" when it times out or the session ends): wisp never approves on its own.
    func answer(_ decision: String) {
        guard let pending = approval else { return }
        pending.reply.send(decision)
        approval = nil
        onAnswered()
        if var s = sessions[pending.sessionId] {
            s.state = decision == "deny" ? .idle : .working
            sessions[pending.sessionId] = s
        }
    }

    private func requestApproval(_ event: HookEvent, session: ClaudeSession, reply: HookReply) {
        // Looking at IntelliJ already, or another request is open: let the terminal ask.
        guard !HostApp.jetbrainsIsFrontmost, approval == nil else {
            reply.send("ask")
            return
        }
        let pending = PendingApproval(sessionId: session.id, project: session.project,
                                      tool: event.toolName ?? "Tool", summary: event.toolSummary,
                                      reply: reply)
        approval = pending
        onNeedsAttention()

        DispatchQueue.main.asyncAfter(deadline: .now() + approvalTimeout) { [weak self] in
            guard let self, self.approval?.id == pending.id else { return }
            self.answer("ask")
        }
    }

    private func pruneStale(now: Date) {
        sessions = sessions.filter { now.timeIntervalSince($0.value.lastEventAt) < staleAfter }
    }
}

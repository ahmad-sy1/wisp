import AppKit
import Foundation

struct MailMessage: Identifiable, Equatable, Sendable {
    let uid: UInt32
    let threadId: UInt64?
    let senderName: String
    let senderAddress: String
    let subject: String
    let date: Date?
    let isRead: Bool

    var id: UInt32 { uid }

    var initial: String {
        senderName.first(where: \.isLetter).map { String($0).uppercased() } ?? "@"
    }
}

/// Gmail inbox over IMAP (imap.gmail.com:993) with a Google app password, so no
/// Google Cloud project is needed. New mail arrives through IMAP IDLE (push, no
/// polling). Read-only: nothing is ever marked as read.
@MainActor
final class MailStore: ObservableObject {
    static let shared = MailStore()

    enum Status: Equatable { case notConfigured, connecting, connected, failed(String) }
    enum Filter { case all, unread }

    @Published private(set) var status: Status = .notConfigured
    @Published private(set) var messages: [MailMessage] = []
    @Published private(set) var unreadCount = 0
    @Published var filter: Filter = .all

    static let addressKey = "gmail-address"
    static let passwordKey = "gmail-app-password"

    /// Recent inbox messages kept for the list (the newest unread ones are added on top).
    private static let listSize = 20
    /// Gmail drops idle connections after ~29 min; re-issue IDLE before that.
    private static let idleRefresh: Duration = .seconds(25 * 60)

    private var loop: Task<Void, Never>?
    private var connection: IMAPConnection?
    private var wakeObserver: NSObjectProtocol?

    var address: String? { Keychain.get(Self.addressKey) }
    var isConfigured: Bool { address != nil && Keychain.get(Self.passwordKey) != nil }

    var visibleMessages: [MailMessage] {
        filter == .all ? messages : messages.filter { !$0.isRead }
    }

    func start() {
        guard loop == nil, isConfigured else { return }
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { _ in
                // Sleep leaves a dead socket behind: reconnect straight away.
                MainActor.assumeIsolated { MailStore.shared.restart() }
            }
        }
        status = .connecting
        loop = Task { [weak self] in await self?.run() }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        let conn = connection
        connection = nil
        Task { await conn?.close() }
    }

    func restart() {
        stop()
        start()
    }

    /// Saves the account in the Keychain and connects.
    func connect(address: String, appPassword: String) {
        let password = appPassword.replacingOccurrences(of: " ", with: "")
        Keychain.set(address.trimmingCharacters(in: .whitespaces), for: Self.addressKey)
        Keychain.set(password, for: Self.passwordKey)
        restart()
    }

    func disconnect() {
        stop()
        Keychain.remove(Self.addressKey)
        Keychain.remove(Self.passwordKey)
        messages = []
        unreadCount = 0
        status = .notConfigured
    }

    /// Opens the thread (or the inbox) in Gmail in the browser.
    func open(_ message: MailMessage? = nil) {
        let account = address?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "0"
        var link = "https://mail.google.com/mail/u/?authuser=\(account)"
        if let thread = message?.threadId { link += "#all/\(String(thread, radix: 16))" }
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    // MARK: - Connection loop

    private func run() async {
        var backoff: Double = 5
        while !Task.isCancelled {
            guard let address, let password = Keychain.get(Self.passwordKey) else { return }
            let conn = IMAPConnection()
            connection = conn
            do {
                try await conn.open(host: "imap.gmail.com", port: 993)
                try await conn.login(user: address, password: password)
                status = .connected
                backoff = 5
                while !Task.isCancelled {
                    try await refresh(conn)
                    try await conn.idle(timeout: Self.idleRefresh)
                }
            } catch is CancellationError {
                break
            } catch let IMAPError.rejected(message)
                where message.localizedCaseInsensitiveContains("AUTHENTICATIONFAILED")
                   || message.localizedCaseInsensitiveContains("credentials") {
                // Wrong address or app password: retrying won't help.
                status = .failed("Inloggen mislukt: controleer adres en app-wachtwoord")
                await conn.close()
                return
            } catch {
                status = .failed("Offline, probeert opnieuw…")
            }
            await conn.close()
            if Task.isCancelled { break }
            try? await Task.sleep(for: .seconds(backoff))
            backoff = min(backoff * 2, 300)
        }
    }

    /// Re-reads the newest messages, the newest unread ones and the unread count.
    private func refresh(_ conn: IMAPConnection) async throws {
        let exists = try await conn.examine("INBOX")
        let unseen = try await conn.unseenUIDs()

        var recent: [MailMessage] = []
        if exists > 0 {
            recent = try await conn.fetchHeaders(range: "\(max(1, exists - Self.listSize + 1)):\(exists)")
        }
        // Unread mail older than the recent window still belongs in the "Ongelezen" filter.
        let known = Set(recent.map(\.uid))
        let olderUnread = unseen.sorted(by: >).prefix(Self.listSize).filter { !known.contains($0) }
        let extra = try await conn.fetchHeaders(uids: Array(olderUnread))

        messages = (recent + extra).sorted { $0.uid > $1.uid }
        unreadCount = unseen.count
    }
}

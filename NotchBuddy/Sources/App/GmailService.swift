import AppKit
import Foundation
@preconcurrency import Network

/// Gmail inbox over IMAP (imap.gmail.com:993) with a Google app password — no Google
/// Cloud project needed. New mail arrives through IMAP IDLE (push, no polling).
/// The inbox is opened read-only (EXAMINE + BODY.PEEK), so nothing is marked as read.
/// Address and app password live in the Keychain only.
@MainActor
final class GmailService {
    static let shared = GmailService()
    private init() {}

    static let addressKey  = "gmail-address"
    static let passwordKey = "gmail-app-password"

    /// How many recent inbox messages the notch keeps.
    private static let listSize = 8
    /// Gmail drops idle connections after ~29 min; re-issue IDLE before that.
    private static let idleRefresh: Duration = .seconds(25 * 60)

    private var loop: Task<Void, Never>?
    private var connection: ImapConnection?
    private var lastSeenUID: UInt32?
    private var bannerWork: DispatchWorkItem?

    var isConfigured: Bool {
        KeychainStore.shared.get(Self.addressKey) != nil && KeychainStore.shared.get(Self.passwordKey) != nil
    }

    func start() {
        guard loop == nil, isConfigured else { return }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            // Sleep leaves a dead socket behind: reconnect straight away.
            MainActor.assumeIsolated { GmailService.shared.restart() }
        }
        loop = Task { [weak self] in await self?.run() }
    }

    func restart() {
        stop()
        start()
    }

    func stop() {
        loop?.cancel()
        loop = nil
        let conn = connection
        connection = nil
        Task { await conn?.close() }
    }

    func disconnect() {
        stop()
        KeychainStore.shared.remove(Self.addressKey)
        KeychainStore.shared.remove(Self.passwordKey)
        let state = AppState.shared
        state.gmailMessages = []
        state.gmailUnread = 0
        state.gmailConnected = false
        state.gmailError = nil
        lastSeenUID = nil
    }

    // MARK: - Connection loop

    private func run() async {
        var backoff: Double = 5
        while !Task.isCancelled {
            guard let address = KeychainStore.shared.get(Self.addressKey),
                  let password = KeychainStore.shared.get(Self.passwordKey) else { return }
            let conn = ImapConnection()
            connection = conn
            do {
                try await conn.open(host: "imap.gmail.com", port: 993)
                try await conn.login(user: address, password: password)
                AppState.shared.gmailConnected = true
                AppState.shared.gmailError = nil
                backoff = 5
                while !Task.isCancelled {
                    try await refresh(conn)
                    _ = try await conn.idle(timeout: Self.idleRefresh)
                }
            } catch is CancellationError {
                break
            } catch let ImapError.rejected(message) where message.localizedCaseInsensitiveContains("AUTHENTICATIONFAILED")
                                                     || message.localizedCaseInsensitiveContains("credentials") {
                // Wrong address/app password: retrying won't help.
                AppState.shared.gmailConnected = false
                AppState.shared.gmailError = "Login failed — check address and app password"
                appendAppLog("gmail.log", "login rejected: \(message)")
                await conn.close()
                return
            } catch {
                AppState.shared.gmailConnected = false
                AppState.shared.gmailError = "Offline — retrying"
                appendAppLog("gmail.log", "connection error: \(error)")
            }
            await conn.close()
            if Task.isCancelled { break }
            try? await Task.sleep(for: .seconds(backoff))
            backoff = min(backoff * 2, 300)
        }
    }

    /// Re-reads the newest inbox messages and the unread count; announces new unread mail.
    private func refresh(_ conn: ImapConnection) async throws {
        let exists = try await conn.examine("INBOX")
        let unread = try await conn.searchUnseenCount()
        var messages: [GmailMessage] = []
        if exists > 0 {
            let from = max(1, exists - Self.listSize + 1)
            messages = try await conn.fetchHeaders(range: "\(from):\(exists)")
                .sorted { $0.uid > $1.uid }
        }

        let state = AppState.shared
        state.gmailMessages = messages
        state.gmailUnread = unread

        let newest = messages.first?.uid
        if let last = lastSeenUID {
            let fresh = messages.filter { $0.uid > last && !$0.isRead }
            if let top = fresh.first { announce(top, extra: fresh.count - 1) }
        }
        if let newest { lastSeenUID = max(lastSeenUID ?? 0, newest) }
    }

    // MARK: - Notification banner

    /// Grows the closed notch into a small banner (sender + subject) for a few seconds.
    private func announce(_ message: GmailMessage, extra: Int) {
        let state = AppState.shared
        SoundEngine.shared.play("pop")
        // Already looking at the island: the list updates by itself.
        guard state.mode != .expanded else { return }
        state.mailBanner = MailBanner(message: message, extra: extra)
        scheduleBannerHide(after: 6)
    }

    private func scheduleBannerHide(after delay: TimeInterval) {
        bannerWork?.cancel()
        let work = DispatchWorkItem {
            MainActor.assumeIsolated {
                // Keep it while the mouse rests on it.
                if AppState.shared.islandHovered {
                    GmailService.shared.scheduleBannerHide(after: 1.5)
                } else {
                    AppState.shared.mailBanner = nil
                }
            }
        }
        bannerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func dismissBanner() {
        bannerWork?.cancel()
        AppState.shared.mailBanner = nil
    }

    // MARK: - Opening Gmail

    func open(_ message: GmailMessage? = nil) {
        let user = KeychainStore.shared.get(Self.addressKey) ?? "0"
        let account = user.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "0"
        var link = "https://mail.google.com/mail/u/?authuser=\(account)"
        if let thread = message?.threadId { link += "#all/\(String(thread, radix: 16))" }
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }
}

// MARK: - Model

struct GmailMessage: Identifiable, Equatable, Sendable {
    let uid: UInt32
    let threadId: UInt64?
    let senderName: String
    let senderAddress: String
    let subject: String
    let date: Date?
    let isRead: Bool

    var id: UInt32 { uid }

    var initial: String {
        senderName.first(where: { $0.isLetter }).map { String($0).uppercased() } ?? "@"
    }

    /// Stable colour per sender for the avatar.
    var avatarColor: String {
        let palette = ["#F4505E", "#F29B38", "#EAB308", "#22C55E", "#00D9B1", "#38BDF8", "#7C5CFF", "#EC4899"]
        let sum = senderAddress.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[sum % palette.count]
    }

    var timeLabel: String {
        guard let date else { return "" }
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "d MMM"
        return f.string(from: date)
    }
}

struct MailBanner: Equatable {
    let message: GmailMessage
    /// Other new messages that arrived at the same time.
    let extra: Int
}

// MARK: - Minimal IMAP client

enum ImapError: Error {
    case closed
    case rejected(String)
    case protocolError(String)
}

/// Just enough IMAP4rev1 for a read-only inbox view: LOGIN, EXAMINE, SEARCH, FETCH, IDLE.
actor ImapConnection {
    private var conn: NWConnection?
    private var buffer = Data()
    private var tagCounter = 0
    private var idleDoneSent = false

    func open(host: String, port: UInt16) async throws {
        let c = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tls)
        conn = c
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let resumed = ResumeOnce()
            c.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumed.claim() { cont.resume() }
                case .failed(let err), .waiting(let err):
                    if resumed.claim() { cont.resume(throwing: err) }
                case .cancelled:
                    if resumed.claim() { cont.resume(throwing: ImapError.closed) }
                default: break
                }
            }
            c.start(queue: .global(qos: .utility))
        }
        let greeting = try await readResponse()
        guard greeting.text.hasPrefix("* OK") else { throw ImapError.protocolError(greeting.text) }
    }

    func close() {
        conn?.cancel()
        conn = nil
    }

    func login(user: String, password: String) async throws {
        _ = try await command("LOGIN \(quoted(user)) \(quoted(password))")
    }

    /// Opens a mailbox read-only; returns its message count.
    func examine(_ mailbox: String) async throws -> Int {
        let lines = try await command("EXAMINE \(quoted(mailbox))")
        for line in lines {
            let parts = line.text.split(separator: " ")
            if parts.count >= 3, parts[0] == "*", parts[2] == "EXISTS", let n = Int(parts[1]) { return n }
        }
        return 0
    }

    func searchUnseenCount() async throws -> Int {
        let lines = try await command("UID SEARCH UNSEEN")
        guard let line = lines.first(where: { $0.text.hasPrefix("* SEARCH") }) else { return 0 }
        return line.text.split(separator: " ").count - 2
    }

    func fetchHeaders(range: String) async throws -> [GmailMessage] {
        let lines = try await command(
            "FETCH \(range) (UID FLAGS X-GM-THRID INTERNALDATE BODY.PEEK[HEADER.FIELDS (FROM SUBJECT)])")
        return lines.compactMap { line in
            guard line.text.hasPrefix("* "), line.text.contains("FETCH"),
                  let uid = Self.number(after: "UID ", in: line.text).flatMap(UInt32.init) else { return nil }
            let headers = MailHeaders.parse(line.literals.first.map { String(decoding: $0, as: UTF8.self) } ?? "")
            let (name, address) = MailHeaders.splitAddress(headers["from"] ?? "")
            return GmailMessage(
                uid: uid,
                threadId: Self.number(after: "X-GM-THRID ", in: line.text).flatMap(UInt64.init),
                senderName: name,
                senderAddress: address,
                subject: headers["subject"].map(MailHeaders.decode) ?? "(no subject)",
                date: Self.internalDate(in: line.text),
                isRead: line.text.contains("\\Seen")
            )
        }
    }

    /// Waits for the server to report a change (new mail, flags) or for `timeout`.
    @discardableResult
    func idle(timeout: Duration) async throws -> Bool {
        let tag = nextTag()
        idleDoneSent = false
        try await send("\(tag) IDLE\r\n")
        let cont = try await readResponse()
        guard cont.text.hasPrefix("+") else { throw ImapError.rejected(cont.text) }

        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            await self?.endIdle()
        }
        defer { timer.cancel() }

        var changed = false
        while true {
            let line = try await readResponse()
            if line.text.hasPrefix("\(tag) ") {
                guard line.text.hasPrefix("\(tag) OK") else { throw ImapError.rejected(line.text) }
                return changed
            }
            if line.text.hasPrefix("* "), line.text.contains("EXISTS") || line.text.contains("EXPUNGE")
                || line.text.contains("FETCH") {
                changed = true
                endIdle()
            }
        }
    }

    private func endIdle() {
        guard !idleDoneSent, let conn else { return }
        idleDoneSent = true
        conn.send(content: Data("DONE\r\n".utf8), completion: .contentProcessed { _ in })
    }

    // MARK: Plumbing

    struct Response {
        var text: String
        var literals: [Data] = []
    }

    private func command(_ cmd: String) async throws -> [Response] {
        let tag = nextTag()
        try await send("\(tag) \(cmd)\r\n")
        var lines: [Response] = []
        while true {
            let line = try await readResponse()
            if line.text.hasPrefix("\(tag) ") {
                guard line.text.hasPrefix("\(tag) OK") else {
                    throw ImapError.rejected(String(line.text.dropFirst(tag.count + 1)))
                }
                return lines
            }
            lines.append(line)
        }
    }

    private func nextTag() -> String {
        tagCounter += 1
        return "C\(tagCounter)"
    }

    private func send(_ text: String) async throws {
        guard let conn else { throw ImapError.closed }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: Data(text.utf8), completion: .contentProcessed { err in
                if let err { cont.resume(throwing: err) } else { cont.resume() }
            })
        }
    }

    /// One logical response: a line plus any `{n}` literals it carries.
    private func readResponse() async throws -> Response {
        var response = Response(text: "")
        while true {
            let line = try await readLine()
            if let open = line.lastIndex(of: "{"), line.hasSuffix("}"),
               let n = Int(line[line.index(after: open)..<line.index(before: line.endIndex)]) {
                response.text += String(line[..<open])
                response.literals.append(try await readBytes(n))
            } else {
                response.text += line
                return response
            }
        }
    }

    private func readLine() async throws -> String {
        while true {
            if let range = buffer.range(of: Data("\r\n".utf8)) {
                let line = buffer[buffer.startIndex..<range.lowerBound]
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                return String(decoding: line, as: UTF8.self)
            }
            try await receiveMore()
        }
    }

    private func readBytes(_ n: Int) async throws -> Data {
        while buffer.count < n { try await receiveMore() }
        let out = buffer.prefix(n)
        buffer.removeFirst(n)
        return Data(out)
    }

    private func receiveMore() async throws {
        guard let conn else { throw ImapError.closed }
        let chunk: Data = try await withCheckedThrowingContinuation { cont in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, err in
                if let err { cont.resume(throwing: err) }
                else if let data, !data.isEmpty { cont.resume(returning: data) }
                else if isComplete { cont.resume(throwing: ImapError.closed) }
                else { cont.resume(returning: Data()) }
            }
        }
        buffer.append(chunk)
    }

    private func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func number(after key: String, in text: String) -> String? {
        guard let r = text.range(of: key) else { return nil }
        return String(text[r.upperBound...].prefix(while: \.isNumber))
    }

    private static func internalDate(in text: String) -> Date? {
        guard let r = text.range(of: "INTERNALDATE \"") else { return nil }
        let rest = text[r.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d-MMM-yyyy HH:mm:ss Z"
        return f.date(from: String(rest[..<end]).trimmingCharacters(in: .whitespaces))
    }
}

/// Guards a continuation against NWConnection reporting several states.
private final class ResumeOnce: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func claim() -> Bool {
        lock.withLock {
            if done { return false }
            done = true
            return true
        }
    }
}

// MARK: - Header parsing

enum MailHeaders {
    /// Unfolds and splits raw header text into lowercased-name → value.
    static func parse(_ raw: String) -> [String: String] {
        let unfolded = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n ", with: " ")
            .replacingOccurrences(of: "\n\t", with: " ")
        var out: [String: String] = [:]
        for line in unfolded.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].lowercased()
            out[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return out
    }

    /// `"Name" <a@b.c>` → ("Name", "a@b.c"); a bare address names itself.
    static func splitAddress(_ value: String) -> (String, String) {
        let decoded = decode(value)
        if let lt = decoded.lastIndex(of: "<"), let gt = decoded.lastIndex(of: ">"), lt < gt {
            let address = String(decoded[decoded.index(after: lt)..<gt])
            var name = decoded[..<lt].trimmingCharacters(in: .whitespaces)
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return (name.isEmpty ? address : name, address)
        }
        return (decoded, decoded)
    }

    /// RFC 2047 encoded words (`=?UTF-8?B?…?=` / `?Q?`), adjacent words joined.
    static func decode(_ value: String) -> String {
        guard value.contains("=?") else { return value }
        let pattern = #"=\?([^?]+)\?([BbQq])\?([^?]*)\?=(\s+(?==\?))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        var result = ""
        var cursor = value.startIndex
        let ns = value as NSString
        for m in regex.matches(in: value, range: NSRange(location: 0, length: ns.length)) {
            guard let whole = Range(m.range, in: value),
                  let cs = Range(m.range(at: 1), in: value),
                  let enc = Range(m.range(at: 2), in: value),
                  let text = Range(m.range(at: 3), in: value) else { continue }
            result += value[cursor..<whole.lowerBound]
            let bytes: Data?
            if value[enc].uppercased() == "B" {
                bytes = Data(base64Encoded: padded(String(value[text])))
            } else {
                bytes = quotedPrintable(String(value[text]))
            }
            let cfEnc = CFStringConvertIANACharSetNameToEncoding(String(value[cs]) as CFString)
            let encoding = cfEnc == kCFStringEncodingInvalidId
                ? String.Encoding.utf8
                : String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEnc))
            result += bytes.flatMap { String(data: $0, encoding: encoding) } ?? String(value[whole])
            cursor = whole.upperBound
        }
        result += value[cursor...]
        return result
    }

    private static func padded(_ b64: String) -> String {
        b64 + String(repeating: "=", count: (4 - b64.count % 4) % 4)
    }

    private static func quotedPrintable(_ s: String) -> Data {
        var out = Data()
        var chars = Array(s.utf8)[...]
        while let c = chars.popFirst() {
            if c == UInt8(ascii: "_") { out.append(0x20) }
            else if c == UInt8(ascii: "="), chars.count >= 2,
                    let byte = UInt8(String(decoding: chars.prefix(2), as: UTF8.self), radix: 16) {
                out.append(byte)
                chars = chars.dropFirst(2)
            } else { out.append(c) }
        }
        return out
    }
}

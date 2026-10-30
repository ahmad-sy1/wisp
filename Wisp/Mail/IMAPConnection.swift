import Foundation
@preconcurrency import Network

enum IMAPError: Error {
    case closed
    case rejected(String)
    case protocolError(String)
}

/// Just enough IMAP4rev1 for the inbox: LOGIN, EXAMINE, SEARCH, FETCH, IDLE, and, only
/// for *Delete* in the mail peek, SELECT and UID MOVE to the trash.
/// Headers are fetched with BODY.PEEK, so nothing is ever marked as read.
actor IMAPConnection {
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
                    if resumed.claim() { cont.resume(throwing: IMAPError.closed) }
                default: break
                }
            }
            c.start(queue: .global(qos: .utility))
        }
        let greeting = try await readResponse()
        guard greeting.text.hasPrefix("* OK") else { throw IMAPError.protocolError(greeting.text) }
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
        for line in try await command("EXAMINE \(quoted(mailbox))") {
            let parts = line.text.split(separator: " ")
            if parts.count >= 3, parts[0] == "*", parts[2] == "EXISTS", let n = Int(parts[1]) { return n }
        }
        return 0
    }

    /// Opens a mailbox read-write. Only used to move one message to the trash.
    func select(_ mailbox: String) async throws {
        _ = try await command("SELECT \(quoted(mailbox))")
    }

    /// The mailbox the server marks as the trash (RFC 6154 `\Trash`): Gmail names it
    /// after the account's language, "[Gmail]/Trash", "[Gmail]/Prullenbak"…
    func trashMailbox() async throws -> String? {
        for line in try await command("LIST \"\" \"*\"") where line.text.contains("\\Trash") {
            // * LIST (\HasNoChildren \Trash) "/" "[Gmail]/Trash"
            guard line.text.hasSuffix("\""),
                  let open = line.text.dropLast().lastIndex(of: "\"") else { continue }
            return String(line.text[line.text.index(after: open)..<line.text.index(before: line.text.endIndex)])
        }
        return nil
    }

    /// Moves one message (by UID) out of the selected mailbox.
    func move(uid: UInt32, to mailbox: String) async throws {
        _ = try await command("UID MOVE \(uid) \(quoted(mailbox))")
    }

    /// UIDs of all unread messages in the open mailbox.
    func unseenUIDs() async throws -> [UInt32] {
        let lines = try await command("UID SEARCH UNSEEN")
        guard let line = lines.first(where: { $0.text.hasPrefix("* SEARCH") }) else { return [] }
        return line.text.split(separator: " ").dropFirst(2).compactMap { UInt32($0) }
    }

    /// Headers for a sequence range (`"41:60"`).
    func fetchHeaders(range: String) async throws -> [MailMessage] {
        try await fetch("FETCH \(range)")
    }

    /// Headers for specific UIDs.
    func fetchHeaders(uids: [UInt32]) async throws -> [MailMessage] {
        guard !uids.isEmpty else { return [] }
        return try await fetch("UID FETCH \(uids.map(String.init).joined(separator: ","))")
    }

    private func fetch(_ prefix: String) async throws -> [MailMessage] {
        let lines = try await command(
            "\(prefix) (UID FLAGS X-GM-THRID INTERNALDATE BODY.PEEK[HEADER.FIELDS (FROM SUBJECT)])")
        return lines.compactMap { line in
            guard line.text.hasPrefix("* "), line.text.contains("FETCH"),
                  let uid = Self.number(after: "UID ", in: line.text).flatMap(UInt32.init) else { return nil }
            let headers = MailHeaders.parse(line.literals.first.map { String(decoding: $0, as: UTF8.self) } ?? "")
            let (name, address) = MailHeaders.splitAddress(headers["from"] ?? "")
            return MailMessage(
                uid: uid,
                threadId: Self.number(after: "X-GM-THRID ", in: line.text).flatMap(UInt64.init),
                senderName: name,
                senderAddress: address,
                subject: headers["subject"].map(MailHeaders.decode) ?? String(localized: "(no subject)"),
                date: Self.internalDate(in: line.text),
                isRead: line.text.contains("\\Seen")
            )
        }
    }

    /// Waits until the server reports a change (new mail, flags) or `timeout` passes.
    @discardableResult
    func idle(timeout: Duration) async throws -> Bool {
        let tag = nextTag()
        idleDoneSent = false
        try await send("\(tag) IDLE\r\n")
        let cont = try await readResponse()
        guard cont.text.hasPrefix("+") else { throw IMAPError.rejected(cont.text) }

        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            await self?.endIdle()
        }
        defer { timer.cancel() }

        var changed = false
        while true {
            let line = try await readResponse()
            if line.text.hasPrefix("\(tag) ") {
                guard line.text.hasPrefix("\(tag) OK") else { throw IMAPError.rejected(line.text) }
                return changed
            }
            if line.text.hasPrefix("* "),
               line.text.contains("EXISTS") || line.text.contains("EXPUNGE") || line.text.contains("FETCH") {
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

    // MARK: - Plumbing

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
                    throw IMAPError.rejected(String(line.text.dropFirst(tag.count + 1)))
                }
                return lines
            }
            lines.append(line)
        }
    }

    private func nextTag() -> String {
        tagCounter += 1
        return "W\(tagCounter)"
    }

    private func send(_ text: String) async throws {
        guard let conn else { throw IMAPError.closed }
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
        guard let conn else { throw IMAPError.closed }
        let chunk: Data = try await withCheckedThrowingContinuation { cont in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, err in
                if let err { cont.resume(throwing: err) }
                else if let data, !data.isEmpty { cont.resume(returning: data) }
                else if isComplete { cont.resume(throwing: IMAPError.closed) }
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
            out[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return out
    }

    /// `"Name" <a@b.c>` → ("Name", "a@b.c"); a bare address names itself.
    static func splitAddress(_ value: String) -> (String, String) {
        let decoded = decode(value)
        if let lt = decoded.lastIndex(of: "<"), let gt = decoded.lastIndex(of: ">"), lt < gt {
            let address = String(decoded[decoded.index(after: lt)..<gt])
            let name = decoded[..<lt].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
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
            let bytes: Data? = value[enc].uppercased() == "B"
                ? Data(base64Encoded: padded(String(value[text])))
                : quotedPrintable(String(value[text]))
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

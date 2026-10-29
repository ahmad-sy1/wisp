import Foundation
import Darwin

/// One Claude Code hook event, already trimmed by `wisp-hook`.
struct HookEvent: Sendable {
    let name: String
    let sessionId: String
    let cwd: String
    let termProgram: String
    let bundleId: String
    let toolName: String?
    /// Short description of what the tool does: a command, a file path, a URL…
    let toolSummary: String?
    let message: String?

    init?(json: [String: Any]) {
        guard let name = json["hook_event_name"] as? String,
              let sessionId = json["session_id"] as? String else { return nil }
        self.name = name
        self.sessionId = sessionId
        cwd = json["cwd"] as? String ?? ""
        termProgram = json["wisp_term_program"] as? String ?? ""
        bundleId = json["wisp_bundle_id"] as? String ?? ""
        toolName = json["tool_name"] as? String
        message = json["message"] as? String
        let input = json["tool_input"] as? [String: Any] ?? [:]
        toolSummary = ["command", "file_path", "path", "url", "pattern", "description"]
            .lazy.compactMap { input[$0] as? String }.first
    }
}

/// The open connection of a permission request; answered exactly once.
final class HookReply: @unchecked Sendable {
    private let fd: Int32
    private let lock = NSLock()
    private var answered = false

    init(fd: Int32) { self.fd = fd }

    /// `decision` is "allow", "deny" or "ask".
    func send(_ decision: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !answered else { return }
        answered = true
        let line = Array("{\"decision\":\"\(decision)\"}\n".utf8)
        _ = line.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
        close(fd)
    }

    deinit { send("ask") }
}

/// Listens on the hook socket. Accepting and reading happen off the main thread;
/// parsed events are handed to the main actor.
final class HookServer: @unchecked Sendable {
    typealias Handler = @MainActor (HookEvent, HookReply?) -> Void

    private let handler: Handler
    private let queue = DispatchQueue(label: "wisp.hook-server")
    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?

    private static let maxLine = 256 * 1024

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func start() {
        let fm = FileManager.default
        try? fm.createDirectory(at: HookSocket.directory, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        unlink(HookSocket.path)

        guard var address = HookSocket.address() else { return log("socket path too long") }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return log("socket() failed") }

        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 16) == 0 else {
            close(fd)
            return log("bind/listen failed: \(String(cString: strerror(errno)))")
        }
        chmod(HookSocket.path, 0o600)
        listenFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptClient() }
        source.resume()
        self.source = source
    }

    private func acceptClient() {
        let client = accept(listenFD, nil, nil)
        guard client >= 0 else { return }
        HookSocket.setTimeout(client, SO_RCVTIMEO, seconds: 2)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.serve(client)
        }
    }

    private func serve(_ fd: Int32) {
        guard let line = readLine(fd),
              let json = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let event = HookEvent(json: json) else {
            close(fd)
            return
        }
        let reply: HookReply?
        if event.name == "PermissionRequest" {
            reply = HookReply(fd: fd)
        } else {
            reply = nil
            close(fd)
        }
        let handler = self.handler
        Task { @MainActor in handler(event, reply) }
    }

    private func readLine(_ fd: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while data.count < Self.maxLine {
            let n = recv(fd, &buffer, buffer.count, 0)
            if n <= 0 { break }
            if let end = buffer[0..<n].firstIndex(of: 0x0A) {
                data.append(contentsOf: buffer[0..<end])
                return data
            }
            data.append(contentsOf: buffer[0..<n])
        }
        return data.isEmpty ? nil : data
    }

    private func log(_ message: String) {
        NSLog("wisp hook server: \(message)")
    }
}

import Darwin
import XCTest

/// Runs the real `wisp-hook` program against a stand-in for wisp's socket, the way Claude
/// Code runs it: JSON on stdin, an answer on stdout. Every run gets its own home folder, so
/// the tests can never reach the wisp that is running on this Mac.
final class HookIntegrationTests: XCTestCase {
    private var home = ""
    private var socketPath: String { home + "/Library/Application Support/wisp/hook.sock" }

    override func setUpWithError() throws {
        continueAfterFailure = false
        // A hook that dies writing to a closed pipe must not take the test process with it.
        signal(SIGPIPE, SIG_IGN)
        // Short on purpose: a Unix socket path has to fit in 104 bytes.
        home = "/tmp/wisp-hook-\(UUID().uuidString.prefix(8))"
        let folder = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)

        // Guard for every test below. No session id: the real wisp would ignore this one.
        let app = try FakeApp(path: socketPath)
        defer { app.stop() }
        app.serve()
        _ = try run(#"{"hook_event_name":"wisp-test-probe"}"#)
        guard app.receivedLine() != nil else {
            throw TestError("wisp-hook didn't use the test's home folder")
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: home)
    }

    // MARK: - Never block Claude Code

    func testExitsAtOnceWhenWispIsNotRunning() throws {
        let hook = try run(permissionRequest)
        XCTAssertEqual(hook.status, 0)
        XCTAssertLessThan(hook.seconds, 3)
        XCTAssertEqual(hook.output, "")
    }

    func testExitsAtOnceOnASocketNobodyListensTo() throws {
        try FakeApp(path: socketPath).stop(removingSocket: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: socketPath))

        let hook = try run(permissionRequest)
        XCTAssertEqual(hook.status, 0)
        XCTAssertLessThan(hook.seconds, 3)
        XCTAssertEqual(hook.output, "")
    }

    func testGivesUpWhenWispStopsReading() throws {
        let app = try FakeApp(path: socketPath)
        defer { app.stop() }

        let hook = try run(hugeEvent)
        XCTAssertEqual(hook.status, 0)
        XCTAssertLessThan(hook.seconds, 5)
    }

    func testSurvivesWispHangingUpWhileItSends() throws {
        let app = try FakeApp(path: socketPath)
        defer { app.stop() }
        app.hangUpAtOnce()

        let hook = try run(hugeEvent)
        XCTAssertEqual(hook.status, 0)
        XCTAssertEqual(hook.output, "")
    }

    func testDoesNotWaitForAnAnswerToOtherEvents() throws {
        let app = try FakeApp(path: socketPath)
        defer { app.stop() }
        app.serve(answer: #"{"decision":"allow"}"#, after: 6)

        let hook = try run(#"{"hook_event_name":"PreToolUse","session_id":"s"}"#)
        XCTAssertEqual(hook.status, 0)
        XCTAssertLessThan(hook.seconds, 3)
        XCTAssertEqual(hook.output, "")
    }

    // MARK: - What it passes on

    func testIgnoresInputThatIsNotJSON() throws {
        let app = try FakeApp(path: socketPath)
        defer { app.stop() }

        let hook = try run("not json")
        XCTAssertEqual(hook.status, 0)
        XCTAssertFalse(app.hasConnectionWaiting)
    }

    func testSkipsSessionsInsideTheClaudeDesktopApp() throws {
        let app = try FakeApp(path: socketPath)
        defer { app.stop() }

        let hook = try run(permissionRequest, bundleId: "com.anthropic.claudefordesktop")
        XCTAssertEqual(hook.status, 0)
        XCTAssertEqual(hook.output, "")
        XCTAssertFalse(app.hasConnectionWaiting)
    }

    func testPassesOnOnlyWhatTheNotchShows() throws {
        let app = try FakeApp(path: socketPath)
        defer { app.stop() }
        app.serve()
        let long = String(repeating: "x", count: 400)
        let event: [String: Any] = [
            "hook_event_name": "PreToolUse",
            "session_id": "s1",
            "cwd": "/repo",
            "tool_response": ["stdout": "output of the tool"],
            "tool_input": [
                "command": long, "description": "list files", "content": "the contents of a file", "timeout": 5,
            ],
        ]

        _ = try run(
            String(decoding: JSONSerialization.data(withJSONObject: event), as: UTF8.self), term: "iTerm.app",
            bundleId: "com.googlecode.iterm2")

        let sent = try XCTUnwrap(app.receivedLine())
        XCTAssertEqual(sent["hook_event_name"] as? String, "PreToolUse")
        XCTAssertEqual(sent["session_id"] as? String, "s1")
        XCTAssertEqual(sent["cwd"] as? String, "/repo")
        XCTAssertNil(sent["tool_response"])
        XCTAssertEqual(sent["tool_input"] as? [String: String], ["command": String(long.prefix(300)), "description": "list files"])
        XCTAssertEqual(sent["wisp_term_program"] as? String, "iTerm.app")
        XCTAssertEqual(sent["wisp_bundle_id"] as? String, "com.googlecode.iterm2")
    }

    // MARK: - Permission requests

    func testWaitsForAnAllowAndPassesItOn() throws {
        let app = try FakeApp(path: socketPath)
        defer { app.stop() }
        app.serve(answer: #"{"decision":"allow"}"#, after: 0.3)

        let hook = try run(permissionRequest)
        XCTAssertEqual(hook.status, 0)
        XCTAssertGreaterThanOrEqual(hook.seconds, 0.3)
        XCTAssertEqual(try decision(in: hook) as NSDictionary, ["behavior": "allow"])
    }

    func testPassesOnADeny() throws {
        let app = try FakeApp(path: socketPath)
        defer { app.stop() }
        app.serve(answer: #"{"decision":"deny"}"#)

        let hook = try run(permissionRequest)
        XCTAssertEqual(hook.status, 0)
        XCTAssertEqual(try decision(in: hook) as NSDictionary, ["behavior": "deny", "message": "Denied in wisp"])
    }

    /// Anything but a clear allow or deny leaves the question to the terminal: no output at all.
    func testNeverApprovesWithoutAClearAnswer() throws {
        let answers = [
            #"{"decision":"ask"}"#, #"{"decision":"yes"}"#, #"{"decision":"allow""#, #"{"decision":true}"#, "{}", "garbage",
        ]
        for answer in answers {
            let app = try FakeApp(path: socketPath)
            defer { app.stop() }
            app.serve(answer: answer)

            let hook = try run(permissionRequest)
            XCTAssertEqual(hook.status, 0, answer)
            XCTAssertEqual(hook.output, "", answer)
        }
    }

    func testExitsCleanlyWhenClaudeCodeIsGoneBeforeTheAnswer() throws {
        let app = try FakeApp(path: socketPath)
        defer { app.stop() }
        app.serve(answer: #"{"decision":"allow"}"#, after: 0.2)

        let hook = try run(permissionRequest, stdoutClosed: true)
        XCTAssertEqual(hook.reason, .exit)
        XCTAssertEqual(hook.status, 0)
    }

    func testLeavesTheQuestionToTheTerminalWhenWispHangsUp() throws {
        let app = try FakeApp(path: socketPath)
        defer { app.stop() }
        app.serve()

        let hook = try run(permissionRequest)
        XCTAssertEqual(hook.status, 0)
        XCTAssertEqual(hook.output, "")
    }

    // MARK: - Running the hook

    private let permissionRequest = #"{"hook_event_name":"PermissionRequest","session_id":"s","tool_name":"Bash"}"#

    /// More than a socket buffer holds, in a field the hook doesn't trim.
    private var hugeEvent: String {
        #"{"hook_event_name":"UserPromptSubmit","session_id":"s","prompt":"\#(String(repeating: "x", count: 1_000_000))"}"#
    }

    private struct HookRun {
        let status: Int32
        let reason: Process.TerminationReason
        let output: String
        let seconds: TimeInterval
    }

    private struct TestError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    private func decision(in hook: HookRun) throws -> [String: Any] {
        let json = try JSONSerialization.jsonObject(with: Data(hook.output.utf8)) as? [String: Any]
        let specific = try XCTUnwrap(json?["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(specific["hookEventName"] as? String, "PermissionRequest")
        return try XCTUnwrap(specific["decision"] as? [String: Any])
    }

    /// Only the variables named here reach the hook: a test run from inside the Claude
    /// desktop app would otherwise pass on its bundle id, and the hook would do nothing.
    private func run(_ stdin: String, term: String? = nil, bundleId: String? = nil, stdoutClosed: Bool = false) throws -> HookRun {
        let process = Process()
        process.executableURL = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("wisp-hook")
        var environment = ["HOME": home, "CFFIXED_USER_HOME": home]
        environment["TERM_PROGRAM"] = term
        environment["__CFBundleIdentifier"] = bundleId
        process.environment = environment

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        let start = Date()
        try process.run()
        if stdoutClosed { try output.fileHandleForReading.close() }
        // On its own queue: a big event doesn't fit in the pipe until the hook reads it.
        let writer = input.fileHandleForWriting
        let bytes = Data(stdin.utf8)
        DispatchQueue.global().async {
            try? writer.write(contentsOf: bytes)
            try? writer.close()
        }
        guard exited.wait(timeout: .now() + 10) == .success else {
            process.terminate()
            throw TestError("wisp-hook was still running after 10 s")
        }
        let seconds = Date().timeIntervalSince(start)
        let printed = stdoutClosed ? Data() : output.fileHandleForReading.readDataToEndOfFile()
        return HookRun(
            status: process.terminationStatus, reason: process.terminationReason, output: String(decoding: printed, as: UTF8.self),
            seconds: seconds)
    }
}

/// Wisp's end of the socket, for one connection.
private final class FakeApp: @unchecked Sendable {
    private let path: String
    private let listener: Int32
    private let finished = DispatchSemaphore(value: 0)
    private var line: Data?

    init(path: String) throws {
        self.path = path
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(listener, 8) == 0 else { throw POSIXError(.EADDRNOTAVAIL) }
    }

    func stop(removingSocket: Bool = true) {
        close(listener)
        if removingSocket { unlink(path) }
    }

    /// True when a client connected and nobody has accepted it yet.
    var hasConnectionWaiting: Bool { waitForConnection(milliseconds: 0) }

    private func waitForConnection(milliseconds: Int32) -> Bool {
        var descriptor = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
        return poll(&descriptor, 1, milliseconds) > 0
    }

    /// Accepts one client and closes it without reading anything.
    func hangUpAtOnce() {
        DispatchQueue.global().async { [self] in
            if waitForConnection(milliseconds: 5000) { close(accept(listener, nil, nil)) }
        }
    }

    /// Accepts one client, reads its line and answers, or just closes when there's no answer.
    func serve(answer: String? = nil, after delay: TimeInterval = 0) {
        DispatchQueue.global().async { [self] in
            defer { finished.signal() }
            guard waitForConnection(milliseconds: 5000) else { return }
            let client = accept(listener, nil, nil)
            defer { close(client) }
            var noSignal: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            var timeout = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

            var received = Data()
            var buffer = [UInt8](repeating: 0, count: 8192)
            while !received.contains(0x0A) {
                let count = recv(client, &buffer, buffer.count, 0)
                if count <= 0 { break }
                received.append(contentsOf: buffer[0..<count])
            }
            line = received

            guard let answer else { return }
            Thread.sleep(forTimeInterval: delay)
            _ = (answer + "\n").withCString { send(client, $0, strlen($0), 0) }
        }
    }

    /// What the client sent, once `serve` is done.
    func receivedLine() -> [String: Any]? {
        guard finished.wait(timeout: .now() + 6) == .success, let line else { return nil }
        return (try? JSONSerialization.jsonObject(with: line.prefix { $0 != 0x0A })) as? [String: Any]
    }
}

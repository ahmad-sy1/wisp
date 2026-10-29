import Foundation
import Darwin

// wisp-hook: Claude Code runs this for each hook event and passes the event as JSON
// on stdin. It forwards a trimmed copy to wisp over a Unix socket.
//
// It must never hold Claude Code up: when wisp is not running the connect fails
// and it exits at once. Only permission requests wait for an answer, and no
// answer (or "ask") means Claude Code asks in the terminal as usual.

let env = ProcessInfo.processInfo.environment

// Sessions inside the Claude desktop app are not shown in the notch.
if env["CLAUDE_CODE_ENTRYPOINT"]?.hasPrefix("claude-desktop") == true { exit(0) }

let input = FileHandle.standardInput.readDataToEndOfFile()
guard var payload = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] else { exit(0) }

let event = payload["hook_event_name"] as? String ?? ""
let waitsForAnswer = event == "PermissionRequest"

// Keep only what the notch shows: no tool output, no file contents.
payload["tool_response"] = nil
if let toolInput = payload["tool_input"] as? [String: Any] {
    var kept: [String: String] = [:]
    for key in ["command", "file_path", "path", "pattern", "url", "description"] {
        if let value = toolInput[key] as? String { kept[key] = String(value.prefix(300)) }
    }
    payload["tool_input"] = kept
}
payload["wisp_term_program"] = env["TERM_PROGRAM"] ?? ""
payload["wisp_bundle_id"] = env["__CFBundleIdentifier"] ?? ""

guard var address = HookSocket.address() else { exit(0) }
let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { exit(0) }
HookSocket.setTimeout(fd, SO_SNDTIMEO, seconds: 1)
HookSocket.setTimeout(fd, SO_RCVTIMEO, seconds: waitsForAnswer ? 115 : 1)

let connected = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard connected == 0, var line = try? JSONSerialization.data(withJSONObject: payload) else { exit(0) }
line.append(0x0A)

var sent = 0
while sent < line.count {
    let n = line.withUnsafeBytes { send(fd, $0.baseAddress! + sent, $0.count - sent, 0) }
    guard n > 0 else { close(fd); exit(0) }
    sent += n
}

guard waitsForAnswer else { close(fd); exit(0) }

var reply = Data()
var buffer = [UInt8](repeating: 0, count: 1024)
while !reply.contains(0x0A) {
    let n = recv(fd, &buffer, buffer.count, 0)
    if n <= 0 { break }
    reply.append(contentsOf: buffer[0..<n])
}
close(fd)

guard let answer = (try? JSONSerialization.jsonObject(with: reply.prefix { $0 != 0x0A })) as? [String: Any],
      let decision = answer["decision"] as? String else { exit(0) }

let behaviour: [String: Any]
switch decision {
case "allow": behaviour = ["behavior": "allow"]
case "deny":  behaviour = ["behavior": "deny", "message": "Geweigerd in wisp"]
default:      exit(0)  // "ask": Claude Code asks in the terminal
}

let output: [String: Any] = [
    "hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": behaviour]
]
if let data = try? JSONSerialization.data(withJSONObject: output) {
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
}
exit(0)

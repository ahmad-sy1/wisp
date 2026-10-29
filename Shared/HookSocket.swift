import Foundation

/// Where wisp listens for Claude Code hook events. Shared by the app and `wisp-hook`.
///
/// Protocol: the hook writes one line of JSON (Claude Code's payload plus a few
/// `wisp_*` fields). Only for `PermissionRequest` does wisp answer, with one line
/// `{"decision": "allow" | "deny" | "ask"}`.
enum HookSocket {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/wisp", isDirectory: true)
    }

    static var path: String { directory.appendingPathComponent("hook.sock").path }

    /// Socket address for `path`, or nil if the path does not fit in `sun_path`.
    static func address() -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count < capacity else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return addr
    }

    static func setTimeout(_ fd: Int32, _ option: Int32, seconds: Int) {
        var tv = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, option, &tv, socklen_t(MemoryLayout<timeval>.size))
    }
}

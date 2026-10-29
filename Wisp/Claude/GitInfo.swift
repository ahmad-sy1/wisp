import Foundation

/// Reads the current git branch straight from `.git/HEAD` (no `git` process).
enum GitInfo {
    static func branch(at path: String) -> String? {
        guard !path.isEmpty, let head = headFile(from: URL(fileURLWithPath: path)),
              let text = try? String(contentsOf: head, encoding: .utf8) else { return nil }
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("ref: refs/heads/") {
            return String(line.dropFirst("ref: refs/heads/".count))
        }
        return line.isEmpty ? nil : String(line.prefix(7))  // detached HEAD: short sha
    }

    /// Walks up from `dir` to the repository root. `.git` is a directory in a normal
    /// checkout and a file (`gitdir: …`) in a worktree or submodule.
    private static func headFile(from dir: URL) -> URL? {
        let fm = FileManager.default
        var current = dir.standardizedFileURL
        while current.path != "/" {
            let git = current.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: git.path, isDirectory: &isDir) {
                if isDir.boolValue { return git.appendingPathComponent("HEAD") }
                guard let pointer = try? String(contentsOf: git, encoding: .utf8),
                      pointer.hasPrefix("gitdir: ") else { return nil }
                let target = pointer.dropFirst("gitdir: ".count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return URL(fileURLWithPath: target, relativeTo: current).appendingPathComponent("HEAD")
            }
            current.deleteLastPathComponent()
        }
        return nil
    }
}

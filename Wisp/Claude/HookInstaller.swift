import Foundation

/// Adds wisp's hooks to `~/.claude/settings.json`.
///
/// Never overwrites blindly: `plan()` builds the merged file and a readable list of
/// changes; nothing is written until the user confirms and `apply()` runs, which
/// first saves a dated backup next to the original.
enum HookInstaller {
    static let events: [(name: String, timeout: Int)] = [
        ("SessionStart", 10), ("UserPromptSubmit", 10),
        ("PreToolUse", 10), ("PostToolUse", 10), ("PostToolUseFailure", 10),
        ("Notification", 10), ("PermissionRequest", 120),
        ("Stop", 10), ("StopFailure", 10), ("SessionEnd", 10),
    ]

    enum Status: Equatable { case notInstalled, installed, otherPath, noHelper }

    struct Change: Identifiable {
        enum Kind { case add, remove }
        let id = UUID()
        let kind: Kind
        let event: String
        let command: String
    }

    struct Plan {
        let settingsURL: URL
        let backupURL: URL
        let updated: Data
        let changes: [Change]
    }

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// The helper inside this app bundle (Contents/MacOS/wisp-hook).
    static var helperPath: String? {
        Bundle.main.url(forAuxiliaryExecutable: "wisp-hook")?.path
    }

    static var command: String? { helperPath.map { "\"\($0)\"" } }

    static func isWisp(_ command: String) -> Bool { command.contains("wisp-hook") }

    static func status(at url: URL = settingsURL, command: String? = command) -> Status {
        guard let command else { return .noHelper }
        let commands = existingCommands(in: (try? readSettings(url)) ?? [:]).filter { isWisp($0.command) }
        if commands.isEmpty { return .notInstalled }
        let all = Set(commands.map(\.command))
        let complete = Set(commands.map(\.event)) == Set(events.map(\.name))
        return all == [command] && complete ? .installed : .otherPath
    }

    static func plan(at url: URL = settingsURL, command: String? = command) throws -> Plan {
        guard let command else { throw InstallError.noHelper }
        var settings = try readSettings(url)
        let before = existingCommands(in: settings)

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        // Drop old wisp entries, keeping everything else.
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept: [[String: Any]] = groups.compactMap { group in
                var group = group
                let entries = (group["hooks"] as? [[String: Any]] ?? []).filter { entry in
                    let cmd = entry["command"] as? String ?? ""
                    return !isWisp(cmd)
                }
                guard !entries.isEmpty else { return nil }
                group["hooks"] = entries
                return group
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        for (event, timeout) in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.append(["hooks": [["type": "command", "command": command, "timeout": timeout]]])
            hooks[event] = groups
        }
        settings["hooks"] = hooks

        let after = existingCommands(in: settings)
        let changes = diff(before: before, after: after)
        let data = try JSONSerialization.data(withJSONObject: settings,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let backup = url.deletingLastPathComponent().appendingPathComponent("settings.json.wisp-backup-\(stamp)")
        return Plan(settingsURL: url, backupURL: backup, updated: data, changes: changes)
    }

    static func apply(_ plan: Plan) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: plan.settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: plan.settingsURL.path) {
            try fm.copyItem(at: plan.settingsURL, to: plan.backupURL)
        }
        var data = plan.updated
        data.append(0x0A)
        try data.write(to: plan.settingsURL, options: .atomic)
    }

    enum InstallError: LocalizedError {
        case noHelper, unreadable

        var errorDescription: String? {
            switch self {
            case .noHelper:   String(localized: "wisp-hook is missing from the app.")
            case .unreadable: String(localized: "~/.claude/settings.json is not valid JSON; nothing was changed.")
            }
        }
    }

    // MARK: - Helpers

    private static func readSettings(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [:] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallError.unreadable
        }
        return json
    }

    private struct Entry: Hashable { let event: String; let command: String }

    private static func existingCommands(in settings: [String: Any]) -> [Entry] {
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        return hooks.flatMap { event, value -> [Entry] in
            (value as? [[String: Any]] ?? []).flatMap { group in
                (group["hooks"] as? [[String: Any]] ?? []).compactMap { entry in
                    (entry["command"] as? String).map { Entry(event: event, command: $0) }
                }
            }
        }
    }

    private static func diff(before: [Entry], after: [Entry]) -> [Change] {
        let b = Set(before), a = Set(after)
        let removed = b.subtracting(a).map { Change(kind: .remove, event: $0.event, command: $0.command) }
        let added = a.subtracting(b).map { Change(kind: .add, event: $0.event, command: $0.command) }
        return (removed + added).sorted { ($0.event, $0.kind == .add ? 1 : 0) < ($1.event, $1.kind == .add ? 1 : 0) }
    }
}

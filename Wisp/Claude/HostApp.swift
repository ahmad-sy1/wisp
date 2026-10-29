import AppKit

/// The app a Claude Code session runs in, from the hook's environment.
struct HostApp: Equatable {
    enum Kind { case jetbrains, vscode, terminal }

    let kind: Kind
    let name: String
    let bundleId: String?

    init(termProgram: String, bundleId: String) {
        let term = termProgram.lowercased()
        let bundle = bundleId.lowercased()
        self.bundleId = bundleId.isEmpty ? nil : bundleId

        if bundle.hasPrefix("com.jetbrains.") || term.contains("jetbrains") {
            kind = .jetbrains
            name = Self.appName(for: bundleId) ?? "IntelliJ IDEA"
        } else if bundle.contains("vscode") || term.contains("vscode") {
            kind = .vscode
            name = "VS Code"
        } else {
            kind = .terminal
            name = Self.appName(for: bundleId) ?? Self.terminalName(term) ?? "Terminal"
        }
    }

    var isIDE: Bool { kind != .terminal }

    /// Opens the project folder in this app (an IDE), or brings the terminal forward.
    @MainActor
    func open(project path: String) {
        let ws = NSWorkspace.shared
        guard let bundleId, let appURL = ws.urlForApplication(withBundleIdentifier: bundleId) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if isIDE, !path.isEmpty {
            ws.open([URL(fileURLWithPath: path)], withApplicationAt: appURL, configuration: config)
        } else {
            ws.openApplication(at: appURL, configuration: config)
        }
    }

    /// True when a JetBrains IDE is the frontmost app: the user is already looking
    /// at its terminal, so permission prompts stay there.
    @MainActor
    static var jetbrainsIsFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.hasPrefix("com.jetbrains.") == true
    }

    private static func appName(for bundleId: String) -> String? {
        guard !bundleId.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    private static func terminalName(_ term: String) -> String? {
        switch term {
        case "apple_terminal": "Terminal"
        case "iterm.app":      "iTerm"
        case "warpterminal":   "Warp"
        case "ghostty":        "Ghostty"
        default:               nil
        }
    }
}

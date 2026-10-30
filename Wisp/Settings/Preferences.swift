import AppKit
import ServiceManagement

/// User preferences, stored in UserDefaults. Secrets never go here (Keychain only).
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @Published var accent: Accent {
        didSet { defaults.set(accent.rawValue, forKey: Key.accent) }
    }

    /// Seconds the panel stays open after the mouse leaves it.
    @Published var closeDelay: Double {
        didSet { defaults.set(closeDelay, forKey: Key.closeDelay) }
    }

    @Published var soundsEnabled: Bool {
        didSet { defaults.set(soundsEnabled, forKey: Key.sounds) }
    }

    @Published private(set) var launchAtLogin: Bool

    /// wisp's own language; `.system` follows macOS. Takes effect after a restart.
    @Published var language: AppLanguage {
        didSet {
            // AppleLanguages in wisp's own domain is what System Settings → Language & Region
            // → Apps writes too, so both places stay in step.
            if let code = language.code { defaults.set([code], forKey: Key.languages) }
            else { defaults.removeObject(forKey: Key.languages) }
        }
    }

    /// The language wisp started with, to tell whether a restart is pending.
    let launchLanguage: AppLanguage

    private let defaults = UserDefaults.standard

    private enum Key {
        static let accent = "accent"
        static let closeDelay = "closeDelay"
        static let sounds = "soundsEnabled"
        static let languages = "AppleLanguages"
    }

    private init() {
        accent = Accent(rawValue: defaults.string(forKey: Key.accent) ?? "") ?? .blue
        closeDelay = defaults.object(forKey: Key.closeDelay) as? Double ?? 0.6
        soundsEnabled = defaults.object(forKey: Key.sounds) as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
        // Only wisp's own domain, not the global language list.
        let own = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[Key.languages] as? [String]
        let current = own?.first.flatMap(AppLanguage.init(code:)) ?? .system
        language = current
        launchLanguage = current
    }

    /// Quits and opens wisp again, for a language change.
    func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("wisp: launch at login change failed: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// The interface languages wisp ships.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english, dutch

    var id: String { rawValue }

    var code: String? {
        switch self {
        case .system:  nil
        case .english: "en"
        case .dutch:   "nl"
        }
    }

    init?(code: String) {
        if code.hasPrefix("nl") { self = .dutch }
        else if code.hasPrefix("en") { self = .english }
        else { return nil }
    }
}

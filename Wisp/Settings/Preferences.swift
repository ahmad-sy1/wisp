import Foundation
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

    /// Look up song lyrics on LRCLIB (sends artist, title, album and duration only).
    @Published var lyricsEnabled: Bool {
        didSet { defaults.set(lyricsEnabled, forKey: Key.lyrics) }
    }

    @Published private(set) var launchAtLogin: Bool

    private let defaults = UserDefaults.standard

    private enum Key {
        static let accent = "accent"
        static let closeDelay = "closeDelay"
        static let sounds = "soundsEnabled"
        static let lyrics = "lyricsEnabled"
    }

    private init() {
        accent = Accent(rawValue: defaults.string(forKey: Key.accent) ?? "") ?? .blue
        closeDelay = defaults.object(forKey: Key.closeDelay) as? Double ?? 0.6
        soundsEnabled = defaults.object(forKey: Key.sounds) as? Bool ?? true
        lyricsEnabled = defaults.object(forKey: Key.lyrics) as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
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

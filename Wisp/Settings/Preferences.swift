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

    /// The global shortcut that opens the notch; nil is off.
    @Published var hotKey: KeyCombo? {
        didSet {
            let data = hotKey.flatMap { try? JSONEncoder().encode($0) }
            defaults.set(data ?? Data(), forKey: Key.hotKey)
        }
    }

    /// What Home shows; `nil` until you choose, so Home shows `HomeLayout.standard`.
    @Published var homeLayout: HomeLayout? {
        didSet { defaults.set(try? JSONEncoder().encode(homeLayout), forKey: Key.homeLayout) }
    }

    /// The closed notch shows the real mini spectrum; off is the fixed equalizer, and no audio tap.
    @Published var miniSpectrum: Bool {
        didSet { defaults.set(miniSpectrum, forKey: Key.miniSpectrum) }
    }

    /// Draws the spectrum less often while the Mac runs on its battery.
    @Published var spectrumBatterySaver: Bool {
        didSet { defaults.set(spectrumBatterySaver, forKey: Key.spectrumBatterySaver) }
    }

    /// Players wisp ignores (Settings → Music). Apps that aren't listed there always show.
    @Published var hiddenMusicSources: Set<MusicSource> {
        didSet { defaults.set(hiddenMusicSources.map(\.rawValue), forKey: Key.hiddenMusicSources) }
    }

    /// Every tab in tab-bar order, shown or not (Settings → Notch).
    @Published var tabOrder: [WispTab] {
        didSet { defaults.set(tabOrder.map(\.rawValue), forKey: Key.tabOrder) }
    }

    /// Tabs switched off in Settings → Notch. Home can't be switched off.
    @Published var hiddenTabs: Set<WispTab> {
        didSet { defaults.set(hiddenTabs.map(\.rawValue), forKey: Key.hiddenTabs) }
    }

    /// The tabs in the tab bar, in order.
    var visibleTabs: [WispTab] { tabOrder.filter { !hiddenTabs.contains($0) } }

    /// wisp's own language; `.system` follows macOS. Takes effect after a restart.
    @Published var language: AppLanguage {
        didSet {
            // AppleLanguages in wisp's own domain is what System Settings → Language & Region
            // → Apps writes too, so both places stay in step.
            if let code = language.code {
                defaults.set([code], forKey: Key.languages)
            } else {
                defaults.removeObject(forKey: Key.languages)
            }
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
        static let tabOrder = "tabOrder"
        static let hiddenTabs = "hiddenTabs"
        static let hotKey = "hotKey"
        static let homeLayout = "homeLayout"
        static let miniSpectrum = "miniSpectrum"
        static let spectrumBatterySaver = "spectrumBatterySaver"
        static let hiddenMusicSources = "hiddenMusicSources"
    }

    private init() {
        accent = Accent(rawValue: defaults.string(forKey: Key.accent) ?? "") ?? .blue
        closeDelay = defaults.object(forKey: Key.closeDelay) as? Double ?? 0.6
        soundsEnabled = defaults.object(forKey: Key.sounds) as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
        // Never set: the standard keys. Saved empty: switched off.
        hotKey = defaults.data(forKey: Key.hotKey).map { try? JSONDecoder().decode(KeyCombo.self, from: $0) } ?? .standard
        homeLayout = defaults.data(forKey: Key.homeLayout).flatMap { try? JSONDecoder().decode(HomeLayout.self, from: $0) }
        miniSpectrum = defaults.object(forKey: Key.miniSpectrum) as? Bool ?? true
        spectrumBatterySaver = defaults.object(forKey: Key.spectrumBatterySaver) as? Bool ?? true
        hiddenMusicSources = Set((defaults.stringArray(forKey: Key.hiddenMusicSources) ?? []).compactMap(MusicSource.init(rawValue:)))
        // Saved order first; tabs added in a later version go at the end.
        let saved = (defaults.stringArray(forKey: Key.tabOrder) ?? []).compactMap(WispTab.init(rawValue:))
        // Home is always the first tab.
        tabOrder = TabBarLayout.order(saved: saved, all: WispTab.allCases, first: .home)
        hiddenTabs = Set((defaults.stringArray(forKey: Key.hiddenTabs) ?? []).compactMap(WispTab.init(rawValue:)))
            .subtracting([.home])
        // Only wisp's own domain, not the global language list.
        let own = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[Key.languages] as? [String]
        let current = own?.first.flatMap(AppLanguage.init(code:)) ?? .system
        language = current
        launchLanguage = current
    }

    /// Moves a tab to where another one is now (drag and drop in Settings → Notch).
    func moveTab(_ tab: WispTab, to target: WispTab) {
        guard tab != target, tab != .home, target != .home, let from = tabOrder.firstIndex(of: tab),
            let to = tabOrder.firstIndex(of: target)
        else { return }
        var order = tabOrder
        order.remove(at: from)
        order.insert(tab, at: to)
        tabOrder = order
    }

    func setTab(_ tab: WispTab, shown: Bool) {
        guard tab != .home else { return }
        if shown { hiddenTabs.remove(tab) } else { hiddenTabs.insert(tab) }
    }

    /// Quits and opens wisp again, for a language change.
    func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    func setMusicSource(_ source: MusicSource, shown: Bool) {
        if shown { hiddenMusicSources.remove(source) } else { hiddenMusicSources.insert(source) }
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
        case .system: nil
        case .english: "en"
        case .dutch: "nl"
        }
    }

    init?(code: String) {
        if code.hasPrefix("nl") { self = .dutch } else if code.hasPrefix("en") { self = .english } else { return nil }
    }
}

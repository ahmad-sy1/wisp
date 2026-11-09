import AppKit
import Combine
import SwiftUI

@main
@MainActor
enum WispMain {
    // NSApplication keeps only a weak reference to its delegate.
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: NotchController?
    private var hookServer: HookServer?
    private var subscriptions: Set<AnyCancellable> = []
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let notch = NotchController()
        notch.openSettings = { [weak self] in self?.openSettings() }
        self.notch = notch
        setUpStatusItem()
        startClaudeHooks(notch: notch)
        startMail(notch: notch)
        startMusic(notch: notch)
        startFocus(notch: notch)
        startGitHub(notch: notch)
        ClipboardStore.shared.start()
        startHotKey(notch: notch)
        #if DEBUG
            // `open wisp.app --args -openOnLaunch mail` opens the panel on that tab (for screenshots).
            if let name = UserDefaults.standard.string(forKey: "openOnLaunch") {
                notch.expand(to: WispTab(rawValue: name) ?? .home)
            }
            // `--args -openOnLaunch agenda -snapshot /tmp/agenda.png` draws the open panel to
            // a PNG once it has settled (data loaded, animations done) and quits.
            // `-settingsPage notch` opens Settings on that page; with `-snapshot` it draws
            // that window instead of the panel.
            let settingsPage = UserDefaults.standard.string(forKey: "settingsPage").flatMap(SettingsPageID.init(rawValue:))
            if let settingsPage {
                SettingsNavigation.shared.page = settingsPage
                // `-addIntegration YES` opens that window on top (Integrations only).
                SettingsNavigation.shared.addingIntegration = UserDefaults.standard.bool(forKey: "addIntegration")
                openSettings()
            }
            if let path = UserDefaults.standard.string(forKey: "snapshot") {
                // `-snapshotDelay 8` for data that takes longer to arrive.
                let delay = UserDefaults.standard.object(forKey: "snapshotDelay") as? Double ?? 3
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    let url = URL(fileURLWithPath: path)
                    if settingsPage != nil { self.snapshotSettings(to: url) } else { notch.snapshot(to: url) }
                    NSApp.terminate(nil)
                }
            }
        #endif
    }

    /// Opening wisp again (Spotlight, Finder, Dock) shows Settings: on a full menu bar
    /// macOS hides the status item behind the notch, so this is the fallback way in.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    // MARK: - Shortcut

    private func startHotKey(notch: NotchController) {
        let hotKey = HotKeyCenter.shared
        hotKey.onPress = { notch.toggleFromKeyboard() }
        Preferences.shared.$hotKey
            .removeDuplicates()
            .sink { hotKey.set($0) }
            .store(in: &subscriptions)
    }

    // MARK: - Claude Code

    private func startClaudeHooks(notch: NotchController) {
        let sessions = ClaudeSessions.shared
        sessions.onNeedsAttention = { notch.expand(to: .home) }
        sessions.onAnswered = { notch.collapseSoon() }
        notch.canCollapse = { sessions.approval == nil }

        let server = HookServer { event, reply in sessions.handle(event, reply: reply) }
        server.start()
        hookServer = server
    }

    // MARK: - Mail

    private func startMail(notch: NotchController) {
        let mail = MailStore.shared
        mail.$unreadCount
            .removeDuplicates()
            .sink { count in
                notch.model.badges[.mail] = count
                notch.model.unreadCount = count
            }
            .store(in: &subscriptions)
        // The unread count on the closed notch, if wanted.
        mail.$unreadCount
            .combineLatest(mail.$showUnreadOnNotch)
            .map { count, show in show && count > 0 }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { on in notch.setMailWings(on) }
            .store(in: &subscriptions)
        mail.onNewMail = { message in
            let focus = FocusStore.shared
            // Quiet while focusing with "Do not disturb", and never over a permission request.
            guard mail.peekNewMail, !(focus.isActive && focus.doNotDisturb),
                ClaudeSessions.shared.approval == nil
            else { return }
            notch.peek(message)
        }
        mail.start()
        #if DEBUG
            // `-mailPeekDemo YES`: peek with a sample message, for snapshots.
            if UserDefaults.standard.bool(forKey: "mailPeekDemo") {
                notch.peek(
                    MailMessage(
                        uid: 0, threadId: nil, senderName: "Sanne de Vries",
                        senderAddress: "sanne@example.com",
                        subject: "Rooster week 45 · kun je dinsdag ruilen met donderdag?",
                        date: .now, isRead: false))
            }
        #endif
    }

    // MARK: - Focus

    private func startFocus(notch: NotchController) {
        let focus = FocusStore.shared
        focus.$phase
            .map { phase in
                switch phase {
                case .running, .paused: true
                case .idle, .finished: false
                }
            }
            .removeDuplicates()
            // @Published fires before the new value is stored; let the wings appear after.
            .receive(on: RunLoop.main)
            .sink { active in notch.setFocusWings(active) }
            .store(in: &subscriptions)
        // Never over a permission request: the panel stays on the question until it is answered.
        focus.onFinished = {
            guard ClaudeSessions.shared.approval == nil else { return }
            notch.expand(to: .focus)
        }
        #if DEBUG
            // `-focusStart YES`: start a session at launch, for snapshots of the running timer.
            if UserDefaults.standard.bool(forKey: "focusStart") { focus.start() }
        #endif
    }

    // MARK: - GitHub

    private func startGitHub(notch: NotchController) {
        let github = GitHubStore.shared
        // Blue count on the tab.
        github.$snapshot
            .combineLatest(github.$notifyReview)
            .map { snapshot, on in on ? snapshot.reviews.count : 0 }
            .removeDuplicates()
            .sink { count in notch.model.badges[.github] = count }
            .store(in: &subscriptions)
        // One status on the notch, and none for a tab that is switched off.
        github.$compact
            .removeDuplicates()
            .combineLatest(DepartureStore.shared.$output.removeDuplicates(), Preferences.shared.$hiddenTabs.removeDuplicates())
            // @Published fires before the new value is stored.
            .receive(on: RunLoop.main)
            .sink { compact, output, hidden in
                notch.setStatus(
                    ClosedNotchStatus.pick(
                        trip: output.map { StatusWings($0) },
                        tripTabOn: !hidden.contains(.departure),
                        github: StatusWings(compact),
                        githubTabOn: !hidden.contains(.github)))
            }
            .store(in: &subscriptions)
        github.onEvent = { event in
            let focus = FocusStore.shared
            // Quiet while focusing with "Do not disturb", and never over a permission request.
            guard !(focus.isActive && focus.doNotDisturb), ClaudeSessions.shared.approval == nil,
                !Preferences.shared.hiddenTabs.contains(.github)
            else { return }
            switch event {
            case .checksFailed where github.notifyFailed:
                notch.flash(Theme.badge)
                if github.tickAnimation { notch.tick() }
            case .checksPassed where github.notifyPassed:
                notch.flash(Theme.ok)
            case .reviewRequested where github.notifyReview, .newActivity where github.notifyComments:
                if github.tickAnimation { notch.tick() }
            default:
                break
            }
        }
        github.start()
        DepartureStore.shared.start()
    }

    // MARK: - Music

    private func startMusic(notch: NotchController) {
        let player = NowPlaying.shared
        let spectrum = Spectrum.shared

        player.$isActive
            .removeDuplicates()
            .sink { active in notch.setMusicWings(active) }
            .store(in: &subscriptions)

        // The spectrum follows what plays and stops when it pauses.
        player.$track
            .map { ($0?.sourceBundleId, $0?.isPlaying == true) }
            .removeDuplicates { $0 == $1 }
            .sink { source, playing in spectrum.setPlayback(source: source, playing: playing) }
            .store(in: &subscriptions)

        Preferences.shared.$hiddenMusicSources
            .dropFirst()
            .removeDuplicates()
            // @Published fires before the new value is stored.
            .receive(on: RunLoop.main)
            .sink { _ in player.sourcesChanged() }
            .store(in: &subscriptions)

        // The closed-notch wings show the mini-spectrum only while the music wings are what
        // the notch really shows (no focus session or status on top), if it isn't switched off.
        notch.model.$musicWings
            .combineLatest(notch.model.$focusWings, notch.model.$statusWings, notch.model.$phase)
            .combineLatest(Preferences.shared.$miniSpectrum)
            // @Published fires before the new value is stored, and `wings` reads what is stored.
            .receive(on: RunLoop.main)
            .map { _, mini in mini && notch.model.isCollapsed && notch.model.wings == .music }
            .removeDuplicates()
            .sink { visible in spectrum.setVisible(visible, by: "wings") }
            .store(in: &subscriptions)

        player.start()
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // A template in the asset catalog, so macOS colours it for the menu bar.
        let icon = NSImage(named: "MenuBarIcon")
        icon?.accessibilityDescription = "wisp"
        item.button?.image = icon

        let menu = NSMenu()
        menu.addItem(withTitle: String(localized: "Open wisp"), action: #selector(openNotch), keyEquivalent: "")
        menu.addItem(withTitle: String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Quit wisp"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for menuItem in menu.items where menuItem.action != #selector(NSApplication.terminate(_:)) {
            menuItem.target = self
        }
        item.menu = menu
        statusItem = item
    }

    @objc private func openNotch() {
        notch?.expand()
    }

    // MARK: - Settings window

    @objc private func openSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(prefs: .shared))
            // The page fills the window, title bar included; don't let SwiftUI add its height.
            host.sizingOptions = []
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.appearance = NSAppearance(named: .darkAqua)
            window.title = String(localized: "Settings — wisp")
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 760, height: 620))
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    #if DEBUG
        /// Draws the Settings window into a PNG (see `-settingsPage`), also on a locked screen:
        /// while snapshotting the pages leave out their scroll view, which `cacheDisplay` can't draw.
        private func snapshotSettings(to url: URL) {
            guard let view = settingsWindow?.contentView,
                let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    #endif
}

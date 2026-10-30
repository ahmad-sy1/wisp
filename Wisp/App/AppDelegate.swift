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
        ClipboardStore.shared.start()
        #if DEBUG
        // `open wisp.app --args -openOnLaunch mail` opens the panel on that tab (for screenshots).
        if let name = UserDefaults.standard.string(forKey: "openOnLaunch") {
            notch.expand(to: WispTab(rawValue: name) ?? .home)
        }
        // `--args -openOnLaunch agenda -snapshot /tmp/agenda.png` draws the open panel to
        // a PNG once it has settled (data loaded, animations done) and quits.
        if let path = UserDefaults.standard.string(forKey: "snapshot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                notch.snapshot(to: URL(fileURLWithPath: path))
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
            .sink { on in notch.setMailWings(on && notch.model.hasNotch) }
            .store(in: &subscriptions)
        mail.onNewMail = { message in
            let focus = FocusStore.shared
            // Quiet while focusing with "Do not disturb", and never over a permission request.
            guard mail.peekNewMail, !(focus.isActive && focus.doNotDisturb),
                  ClaudeSessions.shared.approval == nil else { return }
            notch.peek(message)
        }
        mail.start()
        #if DEBUG
        // `-mailPeekDemo YES`: peek with a sample message, for snapshots.
        if UserDefaults.standard.bool(forKey: "mailPeekDemo") {
            notch.peek(MailMessage(uid: 0, threadId: nil, senderName: "Sanne de Vries",
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
            .sink { active in notch.setFocusWings(active && notch.model.hasNotch) }
            .store(in: &subscriptions)
        focus.onFinished = { notch.expand(to: .focus) }
        #if DEBUG
        // `-focusStart YES`: start a session at launch, for snapshots of the running timer.
        if UserDefaults.standard.bool(forKey: "focusStart") { focus.start() }
        #endif
    }

    // MARK: - Music

    private func startMusic(notch: NotchController) {
        let player = NowPlaying.shared
        let spectrum = Spectrum.shared

        player.$isActive
            .removeDuplicates()
            .sink { active in notch.setMusicWings(active && notch.model.hasNotch) }
            .store(in: &subscriptions)

        // The spectrum follows what plays and stops when it pauses.
        player.$track
            .map { ($0?.sourceBundleId, $0?.isPlaying == true) }
            .removeDuplicates { $0 == $1 }
            .sink { source, playing in spectrum.setPlayback(source: source, playing: playing) }
            .store(in: &subscriptions)

        // The closed-notch wings show the mini-spectrum while they are visible
        // (and not taken over by a focus session).
        notch.model.$musicWings
            .combineLatest(notch.model.$phase, notch.model.$focusWings)
            .map { wings, phase, focus in wings && !focus && phase == .collapsed }
            .removeDuplicates()
            .sink { visible in spectrum.setVisible(visible, by: "wings") }
            .store(in: &subscriptions)

        player.start()
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "wisp")

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
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(prefs: .shared)))
            window.title = String(localized: "Settings — wisp")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

import AppKit
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
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let notch = NotchController()
        notch.openSettings = { [weak self] in self?.openSettings() }
        self.notch = notch
        setUpStatusItem()
        #if DEBUG
        // `open wisp.app --args -openOnLaunch YES` opens the panel right away (for screenshots).
        if UserDefaults.standard.bool(forKey: "openOnLaunch") { notch.expand() }
        #endif
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "circle.circle", accessibilityDescription: "wisp")

        let menu = NSMenu()
        menu.addItem(withTitle: "Open wisp", action: #selector(openNotch), keyEquivalent: "")
        menu.addItem(withTitle: "Instellingen…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Stop wisp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
            window.title = "Settings — wisp"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

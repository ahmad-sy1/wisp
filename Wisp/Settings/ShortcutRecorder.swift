import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The *Shortcut* row of Settings → General (board 10.2): shows the keys; click it, then
/// press new ones.
struct ShortcutRow: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject private var hotKey = HotKeyCenter.shared
    @StateObject private var recorder = ShortcutRecorder()

    var body: some View {
        SettingsRow(title: String(localized: "Shortcut")) {
            if recorder.isRecording {
                Text("Esc cancels · ⌫ turns it off")
            } else if hotKey.failed {
                Text("Another app uses these keys. Choose others.")
                    .foregroundStyle(Theme.warning)
            } else {
                Text("Open the notch with the keyboard")
            }
        } trailing: {
            Button {
                recorder.toggle(prefs: prefs)
            } label: {
                Text(recorder.isRecording ? String(localized: "Type shortcut…")
                                          : prefs.hotKey?.label ?? String(localized: "Off"))
                    .foregroundStyle(recorder.isRecording ? prefs.accent.color : Theme.textPrimary)
                    .monospacedDigit()
            }
            .buttonStyle(.settings)
        }
        .onDisappear { recorder.stop() }
    }
}

/// Listens for one key press while its row asks for it.
@MainActor
private final class ShortcutRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?

    func toggle(prefs: Preferences) {
        isRecording ? stop() : start(prefs: prefs)
    }

    private func start(prefs: Preferences) {
        isRecording = true
        HotKeyCenter.shared.setSuspended(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Typing in the notch isn't meant for the recorder.
            if event.window is NotchPanel { return event }
            MainActor.assumeIsolated { self?.handle(event, prefs: prefs) }
            return nil
        }
        // Gone to another app: don't leave the shortcut suspended.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        HotKeyCenter.shared.setSuspended(false)
    }

    private func handle(_ event: NSEvent, prefs: Preferences) {
        let plain = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        if event.keyCode == UInt16(kVK_Escape) {
            stop()
        } else if plain && (event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete)) {
            prefs.hotKey = nil
            stop()
        } else if let combo = KeyCombo(event: event) {
            prefs.hotKey = combo
            stop()
        } else {
            NSSound.beep()
        }
    }
}

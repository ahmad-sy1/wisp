import AppKit

/// Keys for a window drawn inside Settings, while it is open: a text field would otherwise
/// take the arrows and Return, and Esc would go nowhere.
@MainActor
final class WindowKeyMonitor {
    private var token: Any?

    /// `handle` returns true when it used the key.
    func start(_ handle: @escaping (NSEvent) -> Bool) {
        stop()
        let window = NSApp.keyWindow
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let used = MainActor.assumeIsolated { event.window === window && handle(event) }
            return used ? nil : event
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}

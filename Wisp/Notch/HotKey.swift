import AppKit
import Carbon.HIToolbox

/// A key with modifiers (Carbon's numbers, which is what `RegisterEventHotKey` takes).
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    /// The key as the keyboard labels it when recorded, for keys without a symbol below.
    var character: String?

    /// ⌥ Space (board 10.2).
    static let standard = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))

    /// What a recorded key press means; nil when it has no ⌘, ⌥ or ⌃ (only F-keys may go
    /// without: a plain letter would stop working everywhere else).
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        let code = UInt32(event.keyCode)
        guard modifiers != 0 || Self.functionKeys[code] != nil else { return nil }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        self.init(keyCode: code, modifiers: modifiers, character: event.charactersIgnoringModifiers?.uppercased())
    }

    init(keyCode: UInt32, modifiers: UInt32, character: String? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.character = character
    }

    /// "⌥ Space", "⌃⌘ K".
    var label: String {
        var symbols = ""
        if modifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols.isEmpty ? keyName : "\(symbols) \(keyName)"
    }

    private var keyName: String {
        if keyCode == UInt32(kVK_Space) { return String(localized: "Space") }
        return Self.functionKeys[keyCode] ?? Self.symbolKeys[keyCode] ?? character ?? "?"
    }

    private static let functionKeys: [UInt32: String] = [
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6", UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_F13): "F13", UInt32(kVK_F14): "F14", UInt32(kVK_F15): "F15", UInt32(kVK_F16): "F16",
        UInt32(kVK_F17): "F17", UInt32(kVK_F18): "F18", UInt32(kVK_F19): "F19", UInt32(kVK_F20): "F20",
    ]

    private static let symbolKeys: [UInt32: String] = [
        UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥", UInt32(kVK_Delete): "⌫",
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→", UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Home): "↖", UInt32(kVK_End): "↘", UInt32(kVK_PageUp): "⇞", UInt32(kVK_PageDown): "⇟",
        UInt32(kVK_ForwardDelete): "⌦",
    ]
}

/// The global shortcut that opens the notch. Carbon's hot keys need no Accessibility
/// permission and no event tap: nothing runs until the keys are pressed.
@MainActor
final class HotKeyCenter: ObservableObject {
    static let shared = HotKeyCenter()

    var onPress: () -> Void = {}
    /// macOS or another app refused the shortcut.
    @Published private(set) var failed = false

    private var combo: KeyCombo?
    private var reference: EventHotKeyRef?
    private var handlerInstalled = false
    private var suspended = false

    private init() {}

    /// Registers these keys instead of the current ones; nil turns the shortcut off.
    func set(_ combo: KeyCombo?) {
        self.combo = combo
        update()
    }

    /// Lets go of the keys while the recorder listens, so pressing them records them.
    func setSuspended(_ suspended: Bool) {
        self.suspended = suspended
        update()
    }

    private func update() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        failed = false
        guard let combo, !suspended else { return }
        installHandler()
        let id = EventHotKeyID(signature: OSType(0x7769_7370), id: 1)  // "wisp"
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &reference)
        if status != noErr {
            NSLog("wisp: shortcut \(combo.label) refused (\(status))")
            reference = nil
            failed = true
        }
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                Task { @MainActor in HotKeyCenter.shared.onPress() }
                return noErr
            }, 1, &type, nil, nil)
    }
}

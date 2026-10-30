import Foundation

/// The tabs in the expanded panel, in tab-bar order.
enum WispTab: String, CaseIterable, Identifiable {
    case home, mail, agenda, focus, music, clipboard, notes, system, files

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home:      "house"
        case .mail:      "envelope"
        case .agenda:    "calendar"
        case .focus:     "timer"
        case .music:     "music.note"
        case .clipboard: "clipboard"
        case .notes:     "pencil.line"
        case .system:    "display"
        case .files:     "folder"
        }
    }

    var title: String {
        switch self {
        case .home:      String(localized: "Home")
        case .mail:      String(localized: "Mail")
        case .agenda:    String(localized: "Calendar")
        case .focus:     String(localized: "Focus")
        case .music:     String(localized: "Music")
        case .clipboard: String(localized: "Clipboard")
        case .notes:     String(localized: "Notes")
        case .system:    String(localized: "System")
        case .files:     String(localized: "Files")
        }
    }
}

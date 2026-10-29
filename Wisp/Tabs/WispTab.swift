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
        case .home:      "Home"
        case .mail:      "Mail"
        case .agenda:    "Agenda"
        case .focus:     "Focus"
        case .music:     "Muziek"
        case .clipboard: "Klembord"
        case .notes:     "Notities"
        case .system:    "Systeem"
        case .files:     "Bestanden"
        }
    }
}

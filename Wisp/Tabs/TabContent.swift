import SwiftUI

/// Content area for the selected tab (fixed 150 pt high).
struct TabContent: View {
    let tab: WispTab
    var openSettings: () -> Void = {}

    var body: some View {
        switch tab {
        case .home: HomeTab(sessions: .shared)
        case .mail: MailTab(store: .shared, openSettings: openSettings)
        case .agenda: AgendaTab(agenda: .shared, weather: .shared)
        case .focus: FocusTab(focus: .shared)
        case .clipboard: ClipboardTab(clipboard: .shared)
        case .notes: NotesTab(notes: .shared)
        case .system: SystemTab(stats: .shared)
        case .music: MusicTab(player: .shared)
        // The other tabs get their real view in a later step; until then a calm placeholder.
        default:    PlaceholderTab(tab: tab)
        }
    }
}

struct PlaceholderTab: View {
    let tab: WispTab

    var body: some View {
        Card {
            VStack(spacing: 8) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Theme.textSecondary)
                Text(tab.title)
                    .font(.system(size: 14, weight: .semibold))
                Text("Coming in a later step")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Flat card: #141416 with a hairline #1F1F22 border.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            )
    }
}

import SwiftUI

/// The pages in the Settings sidebar, in order (boards 10.1–10.6).
enum SettingsPageID: String, CaseIterable, Identifiable {
    case general, notch, integrations, agenda, music, focus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:      String(localized: "General")
        case .notch:        String(localized: "Notch")
        case .integrations: String(localized: "Integrations")
        case .agenda:       String(localized: "Calendar & weather")
        case .music:        String(localized: "Music")
        case .focus:        String(localized: "Focus")
        }
    }

    var symbol: String {
        switch self {
        case .general:      "gearshape"
        case .notch:        "rectangle.topthird.inset.filled"
        case .integrations: "powerplug.portrait"
        case .agenda:       "calendar"
        case .music:        "music.note"
        case .focus:        "timer"
        }
    }
}

/// Which page the Settings window shows; shared so other places can open a given page.
@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var page: SettingsPageID = .general
}

/// The Settings window: a sidebar with the pages, the chosen page on the right.
struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var navigation: SettingsNavigation = .shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.cardBorder).frame(width: 1)
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.panel)
        }
        .frame(minWidth: 760, minHeight: 620)
        .ignoresSafeArea()
        .tint(prefs.accent.color)
        .environment(\.colorScheme, .dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 9) {
                Circle()
                    .fill(.white)
                    .frame(width: 8, height: 8)
                    .shadow(color: .white.opacity(0.7), radius: 4)
                Text(verbatim: "wisp")
                    .font(.system(size: 16, weight: .semibold))
            }
            .padding(.leading, 16)
            .padding(.top, 46)
            .padding(.bottom, 18)

            ForEach(SettingsPageID.allCases) { id in
                SidebarItem(id: id, selected: navigation.page == id) { navigation.page = id }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(width: 205)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.card)
    }

    @ViewBuilder
    private var page: some View {
        switch navigation.page {
        case .general:      GeneralPage(prefs: prefs)
        case .notch:        NotchPage(mail: .shared, clipboard: .shared, stats: .shared)
        case .integrations: IntegrationsPage(mail: .shared, nowPlaying: .shared)
        case .agenda:       CalendarPage(agenda: .shared, weather: .shared)
        case .music:        MusicPage(spectrum: .shared)
        case .focus:        FocusPage(focus: .shared)
        }
    }
}

private struct SidebarItem: View {
    let id: SettingsPageID
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: id.symbol)
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text(id.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Theme.activeTab : hovering ? Theme.control : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

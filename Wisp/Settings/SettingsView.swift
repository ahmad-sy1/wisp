import SwiftUI

/// The pages of the Settings window (boards 10.1–10.6, 10.10).
enum SettingsPageID: String, CaseIterable, Identifiable {
    case general, notch, integrations, agenda, departure, github, music, focus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .notch: String(localized: "Notch")
        case .integrations: String(localized: "Integrations")
        case .agenda: String(localized: "Calendar & weather")
        case .departure: String(localized: "Departure")
        case .github: "GitHub"
        case .music: String(localized: "Music")
        case .focus: String(localized: "Focus")
        }
    }

    /// The fixed groups of the sidebar; connected integrations are added below them.
    static let main: [SettingsPageID] = [.general, .notch, .integrations]
    static let features: [SettingsPageID] = [.agenda, .departure, .music, .focus]

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .notch: "rectangle.topthird.inset.filled"
        case .integrations: "powerplug.portrait"
        case .agenda: "calendar"
        case .departure: "tram"
        case .github: WispGlyph.pullRequest
        case .music: "music.note"
        case .focus: "timer"
        }
    }
}

/// Which page the Settings window shows; shared so other places can open a given page.
@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var page: SettingsPageID = .general
    /// *Add integration* is open, over the whole window.
    @Published var addingIntegration = false
    /// The Manage window is open for this service.
    @Published var managingIntegration: IntegrationID?

    /// Closes *Add integration* and goes to where this service is set up.
    func openSetup(of id: IntegrationID) {
        addingIntegration = false
        if IntegrationCatalog.manageSpec(for: id) != nil {
            managingIntegration = id
        } else {
            page = .github
        }
    }
}

/// The Settings window: a sidebar with the pages, the chosen page on the right.
struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var navigation: SettingsNavigation = .shared
    @ObservedObject private var mail = MailStore.shared
    @ObservedObject private var github = GitHubStore.shared
    @ObservedObject private var departure = DepartureStore.shared

    private var integrationRows: [IntegrationRowModel] {
        IntegrationList.rows(
            added: prefs.addedIntegrations,
            connections: IntegrationConnections.current(mail: mail, github: github, departure: departure))
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.cardBorder).frame(width: 1)
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.panel)
        }
        .frame(minWidth: 760, minHeight: 620)
        .overlay {
            if navigation.addingIntegration {
                AddIntegrationOverlay()
            } else if let id = navigation.managingIntegration {
                ManageIntegrationOverlay(id: id)
            }
        }
        // Something else can change the page, such as *Connect GitHub* in the notch.
        .onChange(of: navigation.page) { _, _ in
            navigation.addingIntegration = false
            navigation.managingIntegration = nil
        }
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

            let rows = integrationRows
            let attention = rows.filter(\.state.needsAttention).count
            ForEach(SettingsPageID.main) { id in
                pageItem(id, badge: id == .integrations ? attention : 0)
            }
            sidebarHeader(String(localized: "Features"))
            ForEach(SettingsPageID.features) { pageItem($0) }
            let connected = IntegrationList.sidebarRows(rows)
            if !connected.isEmpty {
                sidebarHeader(String(localized: "Connected"))
                ForEach(connected) { row in
                    // GitHub is the only one with a page so far.
                    SidebarItem(
                        title: row.info.name, selected: navigation.page == .github, hasProblem: row.state.needsAttention,
                        action: { navigation.page = .github },
                        icon: { ServiceIcon(letters: row.info.letters, color: Color(hex: row.info.tint), size: .small) })
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(width: 196)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebar)
    }

    private func pageItem(_ id: SettingsPageID, badge: Int = 0) -> some View {
        SidebarItem(
            title: id.title, selected: navigation.page == id, badge: badge,
            action: { navigation.page = id },
            icon: { Image.wisp(id.symbol).font(.system(size: 13)).frame(width: 18) })
    }

    private func sidebarHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11))
            .foregroundStyle(Theme.textFaint)
            .padding(.leading, 10)
            .padding(.top, 12)
            .padding(.bottom, 2)
    }

    @ViewBuilder
    private var page: some View {
        switch navigation.page {
        case .general: GeneralPage(prefs: prefs)
        case .notch: NotchPage(prefs: prefs, mail: .shared, clipboard: .shared, stats: .shared)
        case .integrations: IntegrationsPage(mail: .shared, nowPlaying: .shared)
        case .agenda: CalendarPage(agenda: .shared, weather: .shared)
        case .departure: DeparturePage(store: .shared, agenda: .shared)
        case .github: GitHubPage(store: .shared)
        case .music: MusicPage(spectrum: .shared)
        case .focus: FocusPage(focus: .shared)
        }
    }
}

private struct SidebarItem<Icon: View>: View {
    let title: String
    let selected: Bool
    var badge = 0
    var hasProblem = false
    let action: () -> Void
    @ViewBuilder let icon: Icon
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if badge > 0 {
                    Text(verbatim: "\(badge)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Circle().fill(Theme.badge))
                }
                if hasProblem {
                    Circle().fill(Theme.badge).frame(width: 7, height: 7)
                }
            }
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: Theme.buttonCorner)
                    .fill(selected ? Theme.activeTab : hovering ? Theme.control : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

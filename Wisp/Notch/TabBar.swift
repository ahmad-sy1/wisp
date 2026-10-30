import SwiftUI

struct TabBar: View {
    @ObservedObject var model: NotchModel
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        HStack(spacing: 2) {
            ForEach(prefs.visibleTabs) { tab in
                TabIconButton(symbol: tab.symbol, label: tab.title,
                              isActive: model.tab == tab,
                              badge: model.badges[tab] ?? 0) {
                    withAnimation(.easeInOut(duration: 0.18)) { model.tab = tab }
                }
            }
            Spacer(minLength: 0)
            if model.tab == .mail {
                MailToolbar(store: .shared)
                    .padding(.trailing, 4)
            } else if model.tab == .agenda {
                AgendaToolbar()
                    .padding(.trailing, 10)
            } else if model.tab == .focus {
                FocusToolbar(focus: .shared)
                    .padding(.trailing, 10)
            } else if model.tab == .clipboard {
                ClipboardToolbar(clipboard: .shared)
                    .padding(.trailing, 4)
            } else if model.tab == .notes {
                NotesToolbar(notes: .shared)
                    .padding(.trailing, 10)
            } else if model.tab == .system {
                SystemToolbar(stats: .shared)
                    .padding(.trailing, 10)
            } else if model.tab == .music {
                MusicToolbar()
                    .padding(.trailing, 10)
            }
            TabIconButton(symbol: "slider.vertical.3", label: String(localized: "Settings"), isActive: false) {
                model.onOpenSettings()
            }
        }
        .onChange(of: prefs.hiddenTabs) { _, hidden in
            if hidden.contains(model.tab) { model.tab = .home }
        }
    }
}

/// 32×28 icon button: grey when idle, white on #2A2A2D when active.
struct TabIconButton: View {
    let symbol: String
    let label: String
    let isActive: Bool
    var badge: Int = 0
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(isActive || hovered ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: Theme.tabSize.width, height: Theme.tabSize.height)
                .background(
                    RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                        .fill(isActive ? Theme.activeTab : hovered ? Theme.controlHover : .clear)
                )
                .overlay(alignment: .topTrailing) {
                    if badge > 0 { CountBadge(count: badge).offset(x: 6, y: -6) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .onHover { hovered = $0 }
    }
}

struct CountBadge: View {
    let count: Int

    var body: some View {
        Text(verbatim: count > 99 ? "99+" : "\(count)")
            .font(.system(size: 9.5, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(minWidth: 16, minHeight: 16)
            .background(Capsule().fill(Theme.badge))
    }
}

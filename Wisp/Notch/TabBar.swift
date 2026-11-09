import SwiftUI

struct TabBar: View {
    @ObservedObject var model: NotchModel
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        let layout = TabBarLayout.split(prefs.visibleTabs)
        HStack(spacing: 2) {
            ForEach(layout.front) { tab in
                TabIconButton(
                    symbol: tab.symbol, label: tab.title, letters: tab.letters,
                    isActive: model.tab == tab,
                    badge: model.badges[tab] ?? 0,
                    badgeColor: tab == .github ? Theme.info : Theme.badge
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) { model.tab = tab }
                }
            }
            if !layout.more.isEmpty {
                MoreTabsButton(
                    count: layout.more.count,
                    isActive: model.moreOpen || layout.more.contains(model.tab),
                    hasBadge: layout.more.contains { (model.badges[$0] ?? 0) > 0 }
                ) {
                    model.moreOpen.toggle()
                }
            }
            Spacer(minLength: 0)
            // Whatever a tab puts here gives way first: the tabs themselves never move.
            Group {
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
            }
            .layoutPriority(-1)
            TabIconButton(symbol: "slider.vertical.3", label: String(localized: "Settings"), isActive: false) {
                model.onOpenSettings()
            }
        }
        .onChange(of: prefs.hiddenTabs) { _, hidden in
            if hidden.contains(model.tab) { model.tab = .home }
        }
        .onChange(of: model.tab) { _, _ in model.moreOpen = false }
        .onChange(of: model.phase) { _, _ in model.moreOpen = false }
    }
}

/// 32×28 icon button: grey when idle, white on #2A2A2D when active.
struct TabIconButton: View {
    let symbol: String
    let label: String
    var letters: String?
    let isActive: Bool
    var badge: Int = 0
    var badgeColor: Color = Theme.badge
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            glyph
                .frame(width: Theme.tabSize.width, height: Theme.tabSize.height)
                .background(
                    RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                        .fill(isActive ? Theme.activeTab : hovered ? Theme.controlHover : .clear)
                )
                .overlay(alignment: .topTrailing) {
                    if badge > 0 { CountBadge(count: badge, color: badgeColor).offset(x: 6, y: -6) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .onHover { hovered = $0 }
    }

    private var foreground: Color { isActive || hovered ? Theme.textPrimary : Theme.textSecondary }

    @ViewBuilder private var glyph: some View {
        if let letters {
            ServiceIcon(letters: letters, color: foreground, size: .small)
        } else {
            Image.wisp(symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(foreground)
        }
    }
}

/// The last spot of a full tab bar: *… 4 ⌄* (board 10.1.2).
private struct MoreTabsButton: View {
    let count: Int
    let isActive: Bool
    let hasBadge: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold))
                Text(verbatim: "\(count)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(isActive || hovered ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: Theme.tabSize.height)
            .background(
                RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                    .fill(isActive ? Theme.activeTab : hovered ? Theme.controlHover : .clear)
            )
            .overlay(alignment: .topTrailing) {
                if hasBadge { Circle().fill(Theme.badge).frame(width: 7, height: 7).offset(x: 2, y: -2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "More tabs"))
        .accessibilityLabel(String(localized: "More tabs"))
        .onHover { hovered = $0 }
    }
}

/// What doesn't fit in the tab bar. It stays inside the panel and scrolls when it is long.
struct MoreTabsMenu: View {
    @ObservedObject var model: NotchModel
    let tabs: [WispTab]
    let editTabs: () -> Void

    private static let rowHeight: CGFloat = 26
    private static let visibleRows = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelScroll {
                VStack(spacing: 0) {
                    ForEach(tabs) { tab in
                        MoreTabsRow(tab: tab, badge: model.badges[tab] ?? 0, isActive: model.tab == tab) {
                            withAnimation(.easeInOut(duration: 0.18)) { model.tab = tab }
                        }
                    }
                }
            }
            .frame(height: CGFloat(min(tabs.count, Self.visibleRows)) * Self.rowHeight)
            Rectangle().fill(Theme.cardBorder).frame(height: 1).padding(.vertical, 4)
            Button(action: editTabs) {
                Text("Edit tabs in Settings…")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .frame(width: 210)
        .background(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous).fill(Theme.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                .strokeBorder(Theme.lineStrong, lineWidth: 1)
        )
    }
}

private struct MoreTabsRow: View {
    let tab: WispTab
    let badge: Int
    let isActive: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let letters = tab.letters {
                    ServiceIcon(letters: letters, color: Theme.textPrimary, size: .small)
                } else {
                    Image.wisp(tab.symbol).font(.system(size: 13)).frame(width: 18)
                }
                Text(tab.title).font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: 6)
                if badge > 0 { CountBadge(count: badge) }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: Theme.smallCorner, style: .continuous)
                    .fill(isActive ? Theme.activeTab : hovered ? Theme.controlHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

struct CountBadge: View {
    let count: Int
    var color: Color = Theme.badge

    var body: some View {
        Text(verbatim: count > 99 ? "99+" : "\(count)")
            .font(.system(size: 9.5, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(minWidth: 16, minHeight: 16)
            .background(Capsule().fill(color))
    }
}

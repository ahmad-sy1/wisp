import SwiftUI

/// Settings → Notch (board 10.1.1): a live preview of the tab bar, Home, and the other tabs:
/// drag to reorder, a switch to show or hide, and each tab's options under a click.
struct NotchPage: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var mail: MailStore
    @ObservedObject var clipboard: ClipboardStore
    @ObservedObject var stats: SystemStats
    @State private var expanded: WispTab?
    /// The tab being dragged; rows move out of its way while it hovers.
    @State private var dragging: WispTab?

    var body: some View {
        let layout = TabBarLayout.split(prefs.visibleTabs)
        SettingsPage(
            title: String(localized: "Notch"),
            subtitle: String(localized: "Choose which tabs you see and drag them into your own order."),
            note: String(
                localized:
                    "Up to 8 tabs fit in the notch. With more, the last spot becomes More and holds the rest. Drag to choose which ones stay up front."
            )
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Preview")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                TabBarPreview(tabs: layout.front, moreCount: layout.more.count)
                Text(summary(layout.front.count, layout.more.count))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }

            SettingsGroup(header: String(localized: "Home · always the first tab")) {
                tabRow(.home, inMore: false)
            }

            SettingsGroup(
                header: String(localized: "Tabs · connected integrations appear here automatically"),
                trailing: String(localized: "\(prefs.visibleTabs.count) on")
            ) {
                ForEach(prefs.tabOrder.filter { $0 != .home }) { tab in
                    tabRow(tab, inMore: layout.more.contains(tab))
                        .onDrag {
                            dragging = tab
                            return NSItemProvider(object: tab.rawValue as NSString)
                        }
                        .onDrop(of: [.text], delegate: TabDropDelegate(target: tab, dragging: $dragging, prefs: prefs))
                }
            }
        }
        .onAppear { stats.refreshWiFi() }
        // macOS doesn't say when a drag ends outside a row; a drag always starts afresh.
        .onDisappear { dragging = nil }
    }

    private func summary(_ front: Int, _ more: Int) -> String {
        let total = front + more
        return more == 0
            ? String(localized: "\(total) tabs on")
            : String(localized: "\(total) tabs on · \(front) fit in the notch · \(more) in More")
    }

    private func tabRow(_ tab: WispTab, inMore: Bool) -> some View {
        TabRow(
            tab: tab, optionCount: optionCount(tab), expanded: expanded == tab, inMore: inMore,
            shown: Binding(
                get: { !prefs.hiddenTabs.contains(tab) },
                set: { prefs.setTab(tab, shown: $0) })
        ) {
            withAnimation(.easeInOut(duration: 0.15)) { expanded = expanded == tab ? nil : tab }
        } options: {
            options(for: tab)
        }
    }

    private func optionCount(_ tab: WispTab) -> Int {
        switch tab {
        case .home: HomeTile.allCases.count
        case .mail: 2
        case .clipboard: 2
        case .system: 1
        default: 0
        }
    }

    @ViewBuilder
    private func options(for tab: WispTab) -> some View {
        switch tab {
        case .home:
            HStack(spacing: 6) {
                ForEach(HomeTile.allCases) { tile in
                    let shown = !prefs.hiddenHomeTiles.contains(tile)
                    HomeTileChip(title: tile.title, shown: shown, color: prefs.accent.color) {
                        prefs.setHomeTile(tile, shown: !shown)
                    }
                }
            }
            .padding(.bottom, 4)
        case .mail:
            OptionToggle(String(localized: "Show new mail in the notch"), isOn: $mail.peekNewMail)
            OptionToggle(String(localized: "Unread count on the closed notch"), isOn: $mail.showUnreadOnNotch)
            if !mail.isConfigured {
                OptionNote(String(localized: "Connect Gmail under Integrations to see your mail."))
            }
        case .clipboard:
            OptionToggle(String(localized: "Keep a clipboard history"), isOn: $clipboard.isEnabled)
            OptionRow(String(localized: "History")) {
                Button("Clear") { clipboard.clear() }
                    .buttonStyle(.settings)
                    .disabled(clipboard.items.isEmpty)
            }
            OptionNote(
                String(
                    localized:
                        "The last \(ClipboardStore.limit) texts you copied, stored only on this Mac. Passwords and one-time codes that apps mark as such are never kept."
                ))
        case .system:
            OptionRow(String(localized: "Wi‑Fi name")) {
                if stats.locationAllowed {
                    Text("Shown").foregroundStyle(Theme.textSecondary)
                } else {
                    Button("Allow…") { stats.requestWiFiName() }
                        .buttonStyle(.settings)
                }
            }
            OptionNote(
                String(
                    localized:
                        "macOS gives apps the name of your Wi‑Fi network only with Location access. wisp uses it for nothing else and never reads where you are."
                ))
        default:
            EmptyView()
        }
    }
}

/// The notch's tab bar as it looks open, Home active.
/// Moves the dragged tab into a row's place as soon as it hovers there.
private struct TabDropDelegate: DropDelegate {
    let target: WispTab
    @Binding var dragging: WispTab?
    let prefs: Preferences

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        withAnimation(.easeInOut(duration: 0.15)) { prefs.moveTab(dragging, to: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

private struct TabBarPreview: View {
    let tabs: [WispTab]
    let moreCount: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                TabPreviewGlyph(tab: tab)
                    .frame(width: Theme.tabSize.width, height: Theme.tabSize.height)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.buttonCorner)
                            .fill(tab == .home ? Theme.activeTab : .clear))
            }
            if moreCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold))
                    Text(verbatim: "\(moreCount)").font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 9)
                .frame(height: Theme.tabSize.height)
                .background(RoundedRectangle(cornerRadius: Theme.buttonCorner).fill(Theme.controlHover))
            }
            Spacer()
            Image(systemName: "slider.vertical.3")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: Theme.tabSize.width, height: Theme.tabSize.height)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16).fill(Theme.panel))
        .overlay(
            UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16)
                .strokeBorder(Theme.cardBorder, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

private struct TabPreviewGlyph: View {
    let tab: WispTab

    var body: some View {
        if let letters = tab.letters {
            ServiceIcon(letters: letters, color: Theme.textPrimary, size: .small)
        } else {
            Image.wisp(tab.symbol)
                .font(.system(size: 13))
                .foregroundStyle(tab == .home ? Theme.textPrimary : Theme.textSecondary)
        }
    }
}

/// ⠿ icon title "2 options" … switch. Drag anywhere on the row; click it for the options.
private struct TabRow<Options: View>: View {
    let tab: WispTab
    let optionCount: Int
    let expanded: Bool
    let inMore: Bool
    @Binding var shown: Bool
    let toggle: () -> Void
    @ViewBuilder var options: Options

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if tab != .home { Grip() }
                Group {
                    glyph
                    Text(tab.title)
                        .font(.system(size: 13.5))
                    if let source {
                        Text(source)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .opacity(shown ? 1 : 0.45)
                if optionCount > 0 {
                    Text(optionCount == 1 ? String(localized: "1 option") : String(localized: "\(optionCount) options"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if inMore && shown {
                    HStack(spacing: 4) {
                        Image(systemName: "ellipsis").font(.system(size: 10, weight: .semibold))
                        Text("In More")
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .overlay(Capsule().strokeBorder(Theme.lineStrong, lineWidth: 1))
                }
                if tab == .home {
                    Text("Always on")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Toggle(tab.title, isOn: $shown)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 15)
            .frame(height: 44)
            .contentShape(Rectangle())
            .onTapGesture { if optionCount > 0 { toggle() } }

            if expanded {
                VStack(alignment: .leading, spacing: 0) { options }
                    .padding(.leading, 47)
                    .padding(.trailing, 15)
                    .padding(.bottom, 10)
            }
        }
    }

    @ViewBuilder private var glyph: some View {
        if let letters = tab.letters {
            ServiceIcon(letters: letters, color: Theme.textPrimary, size: .small).frame(width: 20)
        } else {
            Image.wisp(tab.symbol)
                .font(.system(size: 14))
                .frame(width: 20)
        }
    }

    /// Where a tab gets its data, when that is a service.
    private var source: String? {
        switch tab {
        case .mail: "Gmail"
        case .departure: "NS"
        case .github: String(localized: "Integration")
        default: nil
        }
    }
}

/// *✓ GitHub* with an accent border when on, *+ Notion* in grey when off.
private struct HomeTileChip: View {
    let title: String
    let shown: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: shown ? "checkmark" : "plus")
                    .font(.system(size: 10, weight: .semibold))
                Text(verbatim: title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(shown ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.buttonCorner)
                    .strokeBorder(shown ? color : Theme.cardBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(shown ? .isSelected : [])
    }
}

/// The six-dot drag handle.
private struct Grip: View {
    var body: some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                GridRow {
                    Circle().frame(width: 2.5, height: 2.5)
                    Circle().frame(width: 2.5, height: 2.5)
                }
            }
        }
        .foregroundStyle(Theme.textSecondary.opacity(0.6))
        .frame(width: 12)
        .accessibilityHidden(true)
    }
}

private struct OptionRow<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer()
            trailing
        }
        .frame(minHeight: 34)
    }
}

private struct OptionToggle: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        OptionRow(title) {
            Toggle(title, isOn: $isOn).toggleStyle(.switch).controlSize(.small).labelsHidden()
        }
    }
}

private struct OptionNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
}

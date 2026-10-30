import SwiftUI

/// Settings → Notch (board 10.1): a live preview of the tab bar, and the tabs: drag to
/// reorder, a switch to show or hide, and each tab's options under a click.
struct NotchPage: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var mail: MailStore
    @ObservedObject var clipboard: ClipboardStore
    @ObservedObject var stats: SystemStats
    @State private var expanded: WispTab?
    /// The tab being dragged; rows move out of its way while it hovers.
    @State private var dragging: WispTab?

    var body: some View {
        SettingsPage(title: String(localized: "Notch"),
                     subtitle: String(localized: "Choose which tabs you see and drag them into your own order.")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Preview")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                TabBarPreview(tabs: prefs.visibleTabs)
            }

            SettingsGroup(header: String(localized: "Tabs · click a tab for its options")) {
                ForEach(prefs.tabOrder) { tab in
                    TabRow(tab: tab, optionCount: optionCount(tab), expanded: expanded == tab,
                           shown: Binding(get: { !prefs.hiddenTabs.contains(tab) },
                                          set: { prefs.setTab(tab, shown: $0) })) {
                        withAnimation(.easeInOut(duration: 0.15)) { expanded = expanded == tab ? nil : tab }
                    } options: {
                        options(for: tab)
                    }
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

    private func optionCount(_ tab: WispTab) -> Int {
        switch tab {
        case .mail:      2
        case .clipboard: 2
        case .system:    1
        default:         0
        }
    }

    @ViewBuilder
    private func options(for tab: WispTab) -> some View {
        switch tab {
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
            OptionNote(String(localized: "The last \(ClipboardStore.limit) texts you copied, stored only on this Mac. Passwords and one-time codes that apps mark as such are never kept."))
        case .system:
            OptionRow(String(localized: "Wi‑Fi name")) {
                if stats.locationAllowed {
                    Text("Shown").foregroundStyle(Theme.textSecondary)
                } else {
                    Button("Allow…") { stats.requestWiFiName() }
                        .buttonStyle(.settings)
                }
            }
            OptionNote(String(localized: "macOS gives apps the name of your Wi‑Fi network only with Location access. wisp uses it for nothing else and never reads where you are."))
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

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                Image(systemName: tab.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(tab == .home ? Theme.textPrimary : Theme.textSecondary)
                    .frame(width: Theme.tabSize.width, height: Theme.tabSize.height)
                    .background(RoundedRectangle(cornerRadius: Theme.buttonCorner)
                        .fill(tab == .home ? Theme.activeTab : .clear))
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
        .overlay(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16)
            .strokeBorder(Theme.cardBorder, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// ⠿ icon title "2 options" … switch. Drag anywhere on the row; click it for the options.
private struct TabRow<Options: View>: View {
    let tab: WispTab
    let optionCount: Int
    let expanded: Bool
    @Binding var shown: Bool
    let toggle: () -> Void
    @ViewBuilder var options: Options

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Grip()
                Group {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 14))
                        .frame(width: 20)
                    Text(tab.title)
                        .font(.system(size: 13.5))
                }
                .opacity(shown ? 1 : 0.45)
                if optionCount > 0 {
                    Text(optionCount == 1 ? String(localized: "1 option") : String(localized: "\(optionCount) options"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
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
            .frame(height: 41)
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

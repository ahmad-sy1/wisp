import SwiftUI

// Building blocks for the Settings pages (boards 10.1–10.6): a page with a large title,
// grey group headers above rounded cards, rows split by hairlines, a note at the bottom.

/// One Settings page: title, optional subtitle and top-right action, the groups, a note.
struct SettingsPage<Content: View, Action: View>: View {
    let title: String
    var subtitle: String?
    var note: String?
    @ViewBuilder var action: Action
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 26, weight: .bold))
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    action
                }
                content
                if let note {
                    Text(note)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary.opacity(0.8))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 31)
            .padding(.top, 22)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
    }
}

extension SettingsPage where Action == EmptyView {
    init(title: String, subtitle: String? = nil, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, note: note, action: { EmptyView() }, content: content)
    }
}

/// A grey header above a card whose rows are split by hairlines.
struct SettingsGroup<Content: View>: View {
    var header: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header {
                Text(header)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { Rectangle().fill(Theme.cardBorder).frame(height: 1) }
                        row
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cardBorder, lineWidth: 1))
        }
    }
}

/// A row in a card: title with an optional grey line below, and a control on the right.
struct SettingsRow<Trailing: View, Subtitle: View>: View {
    let title: String
    @ViewBuilder var subtitle: Subtitle
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .fixedSize()
                subtitle
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 15)
        .frame(minHeight: 46)
    }
}

extension SettingsRow where Subtitle == Text? {
    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(title: title, subtitle: { subtitle.map { Text($0) } }, trailing: trailing)
    }
}

extension SettingsRow where Subtitle == Text?, Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: { subtitle.map { Text($0) } }, trailing: { EmptyView() })
    }
}

/// A row with a switch on the right.
struct SettingsToggle: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        _isOn = isOn
    }

    var body: some View {
        SettingsRow(title, subtitle: subtitle) {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

/// "● Installed": a status line with a coloured dot.
struct SettingsStatus: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
        }
    }
}

/// The flat grey buttons in the cards (*Beheer*, *Wijzig*, *Opnieuw installeren*).
struct SettingsButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(configuration.isPressed ? Theme.activeTab : Theme.control))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.cardBorder, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == SettingsButtonStyle {
    static var settings: SettingsButtonStyle { SettingsButtonStyle() }
}

/// A blue text button inside a card (*Alle agenda's tonen*).
struct SettingsLinkRow: View {
    let title: String
    let action: () -> Void
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(prefs.accent.color)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .padding(.horizontal, 15)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The ✕ at the end of a row (remove an integration or a rule).
struct RemoveButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

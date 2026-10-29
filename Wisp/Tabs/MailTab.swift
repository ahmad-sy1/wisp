import SwiftUI

/// Mail: recent Gmail messages in a scrolling list (44 pt rows) inside the fixed card.
struct MailTab: View {
    @ObservedObject var store: MailStore
    let openSettings: () -> Void

    var body: some View {
        Card {
            switch store.status {
            case .notConfigured:
                message("Koppel Gmail om je mail hier te zien.", action: ("Gmail koppelen", openSettings))
            case .failed(let text) where store.messages.isEmpty:
                message(text, action: ("Instellingen", openSettings))
            case .connecting where store.messages.isEmpty:
                message("Verbinden met Gmail…")
            default:
                list
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        let items = store.visibleMessages
        if items.isEmpty {
            message(store.filter == .unread ? "Geen ongelezen mail." : "Je inbox is leeg.")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { mail in
                        MailRow(mail: mail) { store.open(mail) }
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.automatic)
        }
    }

    private func message(_ text: String, action: (String, () -> Void)? = nil) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "envelope")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Theme.textSecondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if let action {
                Button(action.0, action: action.1).buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MailRow: View {
    let mail: MailMessage
    let open: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Circle()
                    .fill(mail.isRead ? Color.clear : Preferences.shared.accent.color)
                    .frame(width: 6, height: 6)
                Avatar(initial: mail.initial, seed: mail.senderAddress)
                Text(mail.senderName)
                    .font(.system(size: 13, weight: mail.isRead ? .regular : .semibold))
                    .lineLimit(1)
                    .frame(width: 150, alignment: .leading)
                Text(mail.subject)
                    .font(.system(size: 13))
                    .foregroundStyle(mail.isRead ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(Self.timeLabel(mail.date))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovered ? Theme.controlHover : .clear)
                .padding(.horizontal, 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Openen in Gmail")
    }

    static func timeLabel(_ date: Date?) -> String {
        guard let date else { return "" }
        if Calendar.current.isDateInToday(date) { return date.formatted(.dateTime.hour().minute()) }
        if Calendar.current.isDateInYesterday(date) { return "gisteren" }
        return date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "nl_NL")))
    }
}

/// Round avatar with the sender's initial on a muted colour that stays the same per sender.
struct Avatar: View {
    let initial: String
    let seed: String
    var size: CGFloat = 26

    private static let palette: [UInt32] = [0x3B5B8C, 0x4A4A52, 0x6E4A8E, 0x2F6B5E, 0x8A5A3A, 0x56607A]

    var body: some View {
        let sum = seed.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        Circle()
            .fill(Color(hex: Self.palette[sum % Self.palette.count]))
            .frame(width: size, height: size)
            .overlay(Text(initial).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white))
    }
}

/// Right side of the tab bar on the Mail tab: Alles / Ongelezen and "open in Gmail".
struct MailToolbar: View {
    @ObservedObject var store: MailStore

    var body: some View {
        HStack(spacing: 6) {
            pill("Alles", .all)
            pill("Ongelezen", .unread)
            Button { store.open() } label: {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: Theme.tabSize.width, height: Theme.tabSize.height)
                    .background(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                        .fill(Theme.control))
            }
            .buttonStyle(.plain)
            .help("Open in Gmail")
        }
    }

    private func pill(_ title: String, _ filter: MailStore.Filter) -> some View {
        let active = store.filter == filter
        return Button { store.filter = filter } label: {
            Text(title)
                .font(.system(size: 12, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: Theme.tabSize.height)
                .background(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                    .fill(active ? Theme.activeTab : Theme.control))
        }
        .buttonStyle(.plain)
    }
}

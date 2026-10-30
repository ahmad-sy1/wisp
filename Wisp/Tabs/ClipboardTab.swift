import SwiftUI

/// Clipboard (board 5): the last 20 texts you copied, newest first, in one scrolling card.
struct ClipboardTab: View {
    @ObservedObject var clipboard: ClipboardStore

    var body: some View {
        Card {
            let items = clipboard.visibleItems
            if !clipboard.isEnabled {
                ClipboardMessage(text: String(localized: "The clipboard history is off in Settings."))
            } else if clipboard.items.isEmpty {
                ClipboardMessage(text: String(localized: "Copy something and it shows up here."))
            } else if items.isEmpty {
                ClipboardMessage(text: String(localized: "Nothing found for “\(clipboard.query)”."))
            } else {
                // Ages are worked out when the tab opens; they don't need to tick.
                let now = Date()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            ClipboardRow(item: item, now: now) { clipboard.copy(item) }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.automatic)
            }
        }
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    let now: Date
    let copy: () -> Void
    @State private var copied = false
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        HStack(spacing: 10) {
            KindTile(kind: item.kind)
            Text(item.text.replacingOccurrences(of: "\n", with: " ⏎ "))
                .font(item.kind == .code ? .system(size: 12, design: .monospaced) : .system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(String(item.text.prefix(500)))
            Text(Self.age(item.copiedAt, now: now))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .fixedSize()
            Button {
                copy()
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
            } label: {
                Text(copied ? String(localized: "Copied") : String(localized: "Copy"))
                    .foregroundStyle(copied ? prefs.accent.color : Theme.textPrimary)
                    .frame(minWidth: 58)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
    }

    /// "now", "2 min", "1 h", "3 d".
    static func age(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 1 { return String(localized: "now") }
        if minutes < 60 { return String(localized: "\(minutes) min") }
        if minutes < 24 * 60 { return String(localized: "\(minutes / 60) h") }
        return String(localized: "\(minutes / (24 * 60)) d")
    }
}

/// "URL", "</>" or "Aa" on a small grey tile.
private struct KindTile: View {
    let kind: ClipboardItem.Kind

    var body: some View {
        Text(verbatim: label)
            .font(.system(size: kind == .url ? 10 : 11, weight: .bold))
            .foregroundStyle(Theme.textSecondary)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.control))
    }

    private var label: String {
        switch kind {
        case .url: "URL"
        case .code: "</>"
        case .text: "Aa"
        }
    }
}

private struct ClipboardMessage: View {
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "clipboard")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Theme.textSecondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Right side of the tab bar on the Clipboard tab: the search field.
struct ClipboardToolbar: View {
    @ObservedObject var clipboard: ClipboardStore

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            TextField("Search clipboard", text: $clipboard.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !clipboard.query.isEmpty {
                Button { clipboard.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 190, height: Theme.tabSize.height)
        .background(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous).fill(Theme.control))
        .onDisappear { clipboard.query = "" }
    }
}

import AppKit
import SwiftUI

/// Connects the window to what is really set up, and dims Settings behind it.
struct AddIntegrationOverlay: View {
    @ObservedObject private var navigation = SettingsNavigation.shared
    @ObservedObject private var mail = MailStore.shared
    @ObservedObject private var github = GitHubStore.shared
    @ObservedObject private var departure = DepartureStore.shared

    private var added: Set<IntegrationID> {
        var result = Set<IntegrationID>()
        if mail.isConfigured { result.insert(.gmail) }
        if github.status != .disconnected { result.insert(.github) }
        if departure.hasNSKey { result.insert(.ns) }
        return result
    }

    var body: some View {
        ModalBackdrop(close: close) {
            AddIntegrationWindow(added: added, choose: { navigation.openSetup(of: $0) }, close: close)
        }
    }

    private func close() {
        navigation.addingIntegration = false
    }
}

/// *Add integration* (board 10.3.1): the list on the left, the chosen service on the right.
private struct AddIntegrationWindow: View {
    let added: Set<IntegrationID>
    let choose: (IntegrationID) -> Void
    let close: () -> Void

    @State private var query = ""
    @State private var filter = IntegrationFilter.all
    @State private var selection: IntegrationID?
    @State private var keys = WindowKeyMonitor()
    @FocusState private var searchFocused: Bool

    private var listing: IntegrationListing {
        IntegrationCatalog.listing(added: added, filter: filter, query: query)
    }

    private var current: IntegrationInfo? {
        let ordered = listing.ordered
        return ordered.first { $0.id == selection } ?? ordered.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.cardBorder).frame(height: 1)
            HStack(spacing: 0) {
                list
                Rectangle().fill(Theme.cardBorder).frame(width: 1)
                detail.frame(width: 250)
            }
            Rectangle().fill(Theme.cardBorder).frame(height: 1)
            footer
        }
        .frame(width: 680, height: 556)
        .modalSurface()
        .onAppear {
            keys.start(handle)
            // A turn later: the field can't take focus while it is being added to the window.
            DispatchQueue.main.async { searchFocused = true }
        }
        .onDisappear { keys.stop() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add integration")
                        .font(.system(size: 17, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel("Close")
            }
            SearchField(
                text: $query,
                prompt: String(localized: "Search by name or what it does…"),
                isFocused: $searchFocused)
            HStack(spacing: 6) {
                ForEach(IntegrationCatalog.filters(), id: \.self) { item in
                    let count = IntegrationCatalog.count(added: added, filter: item)
                    FilterChip(title: title(of: item), count: count, active: item == filter) {
                        filter = item
                        selection = nil
                    }
                    .disabled(count == 0)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var subtitle: String {
        String(localized: "\(IntegrationCatalog.all.count) integrations · \(added.count) added")
    }

    private func title(of filter: IntegrationFilter) -> String {
        switch filter {
        case .all: String(localized: "All")
        case .added: String(localized: "Added")
        case .category(let category): category.title
        }
    }

    // MARK: - List

    @ViewBuilder private var list: some View {
        if listing.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                #if DEBUG
                    if UserDefaults.standard.string(forKey: "snapshot") != nil {
                        rows.frame(maxHeight: .infinity, alignment: .top)
                    } else {
                        scrolling(proxy)
                    }
                #else
                    scrolling(proxy)
                #endif
            }
        }
    }

    private func scrolling(_ proxy: ScrollViewProxy) -> some View {
        ScrollView { rows }
            .onChange(of: selection) { _, id in
                if let id { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) } }
            }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 2) {
            section(String(localized: "Available · \(listing.available.count)"), listing.available)
            section(String(localized: "Added · \(listing.added.count)"), listing.added)
        }
        .padding(10)
    }

    @ViewBuilder private func section(_ title: String, _ items: [IntegrationInfo]) -> some View {
        if !items.isEmpty {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textFaint)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 4)
            ForEach(items) { item in
                IntegrationListRow(item: item, selected: item.id == current?.id) {
                    selection = item.id
                }
                .id(item.id)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: Theme.iconCorner, style: .continuous)
                .fill(Theme.control)
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary))
            Text(emptyTitle)
                .font(.system(size: 14, weight: .semibold))
                .multilineTextAlignment(.center)
            Text("Try another word, like “mail” or “train”.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            RequestLink(title: String(localized: "Request this integration"), query: query)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? String(localized: "Nothing here yet")
            : String(localized: "No integration for “\(trimmed)”")
    }

    // MARK: - Detail

    @ViewBuilder private var detail: some View {
        if let item = current {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    ServiceIcon(letters: item.letters, color: Color(hex: item.tint), size: .header)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: item.name).font(.system(size: 15, weight: .semibold))
                        Text(item.category.title)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Text(item.details)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textLabel)
                    .lineSpacing(2)
                    .padding(.top, 12)
                Text("In your notch")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.top, 12)
                NotchPreview(text: item.notchPreview, color: Color(hex: item.tint))
                    .padding(.top, 6)
                VStack(spacing: 8) {
                    fact(String(localized: "Connect with"), item.connectWith)
                    fact(String(localized: "Setup"), String(localized: "\(item.setupMinutes) min"))
                }
                .padding(.top, 12)
                Spacer(minLength: 10)
                action(for: item)
                Text("Keys stay in your Mac's Keychain. Nothing is sent anywhere except to \(item.vendor) itself.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            }
            .padding(16)
        } else {
            Color.clear
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(Theme.textPrimary).lineLimit(1)
        }
        .font(.system(size: 12))
    }

    @ViewBuilder private func action(for item: IntegrationInfo) -> some View {
        if added.contains(item.id) {
            Button {
                choose(item.id)
            } label: {
                Text("Manage").frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle(height: Theme.windowButtonHeight))
        } else {
            Button {
                choose(item.id)
            } label: {
                Text("Add \(item.name)").frame(maxWidth: .infinity)
            }
            .buttonStyle(AccentButtonStyle(height: Theme.windowButtonHeight))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 16) {
            hint("↑↓", String(localized: "navigate"))
            hint("↩", String(localized: "add"))
            hint("esc", String(localized: "close"))
            Spacer()
            RequestLink(title: String(localized: "Missing one? Request an integration"), query: "", muted: true)
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 18)
        .frame(height: 38)
    }

    private func hint(_ key: String, _ title: String) -> some View {
        HStack(spacing: 5) {
            Text(verbatim: key)
            Text(title)
        }
        .foregroundStyle(Theme.textFaint)
    }

    // MARK: - Keys

    /// Returns true when the key was used here.
    private func handle(_ event: NSEvent) -> Bool {
        // Caps Lock doesn't change a shortcut; arrows and the keypad carry flags of their own.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "k" {
            searchFocused = true
            return true
        }
        guard flags.isEmpty else { return false }
        switch event.keyCode {
        case 53:
            close()
        case 36, 76:
            guard let id = current?.id else { return false }
            choose(id)
        case 126:
            selection = IntegrationCatalog.neighbour(of: current?.id, in: listing.ordered, offset: -1)
        case 125:
            selection = IntegrationCatalog.neighbour(of: current?.id, in: listing.ordered, offset: 1)
        default:
            return false
        }
        return true
    }
}

private struct IntegrationListRow: View {
    let item: IntegrationInfo
    let selected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                ServiceIcon(letters: item.letters, color: Color(hex: item.tint))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.name).font(.system(size: 13, weight: .semibold))
                    Text(item.summary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("\(item.setupMinutes) min")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 8)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                    .fill(selected ? Theme.control : hovered ? Theme.rowHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovered = $0 }
    }
}

/// A slice of the closed notch with the line this service would show.
private struct NotchPreview: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: Theme.buttonCorner, bottomTrailingRadius: Theme.buttonCorner)
                .fill(Color.black)
        )
        .overlay(
            UnevenRoundedRectangle(bottomLeadingRadius: Theme.buttonCorner, bottomTrailingRadius: Theme.buttonCorner)
                .strokeBorder(Theme.lineStrong, lineWidth: 1)
        )
    }
}

/// Opens a new GitHub issue in the browser, with what was searched for as its title.
private struct RequestLink: View {
    let title: String
    let query: String
    var muted = false

    @ObservedObject private var prefs = Preferences.shared

    private var url: URL? {
        var parts = URLComponents(string: "https://github.com/ahmad-sy1/wisp/issues/new")
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        parts?.queryItems = [URLQueryItem(name: "title", value: "Integration request: \(trimmed)")]
        return parts?.url
    }

    var body: some View {
        Button(title) {
            if let url { NSWorkspace.shared.open(url) }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .font(.system(size: muted ? 11.5 : 12))
        .foregroundStyle(muted ? Theme.textSecondary : prefs.accent.color)
    }
}

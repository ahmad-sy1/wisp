import SwiftUI

/// Settings → Integrations (board 10.3.4): what needs doing on top, what works below it,
/// and *Add integration*.
struct IntegrationsPage: View {
    @ObservedObject var mail: MailStore
    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var github = GitHubStore.shared
    @ObservedObject private var departure = DepartureStore.shared
    @ObservedObject private var navigation = SettingsNavigation.shared
    @State private var removing: IntegrationInfo?

    private var rows: [IntegrationRowModel] {
        IntegrationList.rows(
            added: prefs.addedIntegrations,
            connections: IntegrationConnections.current(mail: mail, github: github, departure: departure))
    }

    var body: some View {
        let rows = rows
        let attention = rows.filter(\.state.needsAttention)
        let working = rows.filter { !$0.state.needsAttention }
        SettingsPage(
            title: String(localized: "Integrations"),
            subtitle: String(localized: "Only what you use is listed here. Add what you need."),
            note: String(
                localized:
                    "Connected integrations with their own choices get a page in the sidebar. Keys are kept in your Mac's Keychain."
            )
        ) {
            Button {
                navigation.addingIntegration = true
            } label: {
                Label("Add integration", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: Theme.windowButtonHeight)
                    .background(RoundedRectangle(cornerRadius: Theme.buttonCorner).fill(prefs.accent.color))
            }
            .buttonStyle(.plain)
            .fixedSize()
        } content: {
            if !attention.isEmpty {
                SettingsGroup(header: String(localized: "Needs attention · \(attention.count)")) {
                    ForEach(attention) { row($0) }
                }
            }
            // Music works by itself, so it counts too.
            SettingsGroup(header: String(localized: "Connected · \(working.count + 1)")) {
                ForEach(working) { row($0) }
                MusicRow(status: musicStatus)
            }
        }
        .confirmationDialog(
            String(localized: "Remove \(removing?.name ?? "")?"),
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            presenting: removing
        ) { info in
            Button("Remove", role: .destructive) { remove(info.id) }
        } message: { _ in
            Text("wisp disconnects and deletes its key from your Keychain.")
        }
    }

    private func row(_ model: IntegrationRowModel) -> some View {
        IntegrationRow(
            model: model,
            manage: { navigation.openSetup(of: model.id) },
            options: { navigation.page = .github },
            retry: model.id == .gmail ? { mail.restart() } : nil,
            remove: {
                if model.state == .notSetUp {
                    remove(model.id)
                } else {
                    removing = model.info
                }
            })
    }

    private func remove(_ id: IntegrationID) {
        prefs.addedIntegrations.remove(id)
        switch id {
        case .gmail: mail.disconnect()
        case .github: github.disconnect()
        case .ns: departure.setNSKey(nil)
        }
    }

    private var musicStatus: String {
        if let source = nowPlaying.track?.sourceName {
            return String(localized: "\(source) · works automatically")
        }
        return String(localized: "Works automatically")
    }
}

private struct IntegrationRow: View {
    let model: IntegrationRowModel
    let manage: () -> Void
    let options: () -> Void
    let retry: (() -> Void)?
    let remove: () -> Void

    private var status: (text: String, color: Color?, failed: Bool) {
        switch model.state {
        case .notSetUp: (String(localized: "Added · not connected yet"), nil, false)
        case .connection(.connecting): (String(localized: "Connecting…"), Theme.info, false)
        case .connection(.connected(let detail)): (detail, Theme.ok, false)
        case .connection(.problem(let message)): (message, Theme.badge, true)
        }
    }

    private var isProblem: Bool {
        if case .connection(.problem) = model.state { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 12) {
            ServiceIcon(letters: model.info.letters, color: Color(hex: model.info.tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: model.info.name)
                    .font(.system(size: 13.5, weight: .semibold))
                IntegrationStatusLine(text: status.text, dot: status.color, failed: status.failed)
            }
            Spacer(minLength: 10)
            actions
            RemoveButton(help: String(localized: "Remove"), action: remove)
        }
        .padding(.leading, 15)
        .padding(.trailing, 12)
        .frame(height: 58)
    }

    @ViewBuilder private var actions: some View {
        if model.state == .notSetUp {
            Button("Set up in Manage", action: manage).buttonStyle(AccentButtonStyle())
        } else {
            if model.info.hasOptions, !isProblem {
                Button(action: options) {
                    HStack(spacing: 4) {
                        Text("Options")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            if isProblem, let retry {
                Button("Retry", action: retry).buttonStyle(OutlinedButtonStyle())
            }
            Button("Manage", action: manage).buttonStyle(.settings)
        }
    }
}

/// Music has nothing to fill in or take away, so it has no buttons.
private struct MusicRow: View {
    let status: String

    var body: some View {
        HStack(spacing: 12) {
            ServiceIcon(letters: "M", color: Theme.ok)
            VStack(alignment: .leading, spacing: 2) {
                Text("Music").font(.system(size: 13.5, weight: .semibold))
                IntegrationStatusLine(text: status, dot: Theme.ok, failed: false)
            }
            Spacer(minLength: 10)
        }
        .padding(.horizontal, 15)
        .frame(height: 58)
    }
}

/// A dot and a line of text; without a colour the dot is a hollow ring.
private struct IntegrationStatusLine: View {
    let text: String
    let dot: Color?
    let failed: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let dot {
                Circle().fill(dot).frame(width: 6, height: 6)
            } else {
                Circle().strokeBorder(Theme.textSecondary, lineWidth: 1.5).frame(width: 7, height: 7)
            }
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(failed ? Theme.redText : Theme.textSecondary)
                .lineLimit(1)
        }
    }
}

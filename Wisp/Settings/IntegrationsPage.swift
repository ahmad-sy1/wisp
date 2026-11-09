import SwiftUI

/// Settings → Integrations (board 10.3): only what's in use, each with *Manage* and ✕,
/// and *Add integration* on top. Gmail and Music today; GitHub, Notion and WHOOP join
/// when they exist.
struct IntegrationsPage: View {
    @ObservedObject var mail: MailStore
    @ObservedObject var nowPlaying: NowPlaying
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var github = GitHubStore.shared
    @ObservedObject private var departure = DepartureStore.shared
    @ObservedObject private var navigation = SettingsNavigation.shared
    @State private var confirmRemoveGmail = false

    var body: some View {
        SettingsPage(
            title: String(localized: "Integrations"),
            subtitle: String(localized: "Only what you use is listed here. Add what you need."),
            note: String(
                localized:
                    "Keys and passwords are kept safely in your Mac's Keychain. Removing an integration disconnects it and deletes its key."
            )
        ) {
            Button {
                navigation.addingIntegration = true
            } label: {
                Label("Add integration", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: Theme.buttonCorner).fill(prefs.accent.color))
            }
            .buttonStyle(.plain)
            .fixedSize()
        } content: {
            SettingsGroup(header: String(localized: "In use")) {
                if mail.isConfigured {
                    IntegrationRow(
                        name: "Gmail", color: Color(hex: 0xEA4335), status: gmailStatus,
                        manage: { navigation.managingIntegration = .gmail },
                        remove: { confirmRemoveGmail = true })
                }
                if github.status != .disconnected {
                    IntegrationRow(
                        name: "GitHub", color: Color(hex: 0xF0F6FC), status: githubStatus,
                        manage: { SettingsNavigation.shared.page = .github },
                        remove: { github.disconnect() })
                }
                if departure.hasNSKey {
                    IntegrationRow(
                        name: "NS", color: Theme.nsYellow, status: String(localized: "Key in your Keychain"),
                        manage: { navigation.managingIntegration = .ns },
                        remove: { departure.setNSKey(nil) })
                }
                IntegrationRow(
                    name: String(localized: "Music"), color: Theme.ok, status: musicStatus,
                    manage: { SettingsNavigation.shared.page = .music },
                    remove: nil)
            }
        }
        .confirmationDialog(String(localized: "Remove Gmail?"), isPresented: $confirmRemoveGmail) {
            Button("Remove", role: .destructive) { mail.disconnect() }
        } message: {
            Text("wisp disconnects and deletes the app password from your Keychain.")
        }
    }

    private var gmailStatus: String {
        switch mail.status {
        case .notConfigured: String(localized: "Not connected")
        case .connecting: String(localized: "Connecting…")
        case .connected: String(localized: "Connected · \(mail.address ?? "")")
        case .failed(let error): error
        }
    }

    private var githubStatus: String {
        switch github.status {
        case .disconnected: String(localized: "Not connected")
        case .connecting: String(localized: "Connecting…")
        case .connected(let login): String(localized: "Connected · @\(login)")
        case .failed(let message): message
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
    let name: String
    let color: Color
    let status: String
    let manage: () -> Void
    let remove: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .font(.system(size: 13.5, weight: .semibold))
                Text(status)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Button("Manage", action: manage)
                .buttonStyle(.settings)
            if let remove {
                RemoveButton(help: String(localized: "Remove"), action: remove)
            } else {
                Color.clear.frame(width: 24, height: 24)
            }
        }
        .padding(.leading, 15)
        .padding(.trailing, 12)
        .frame(height: 52)
    }
}

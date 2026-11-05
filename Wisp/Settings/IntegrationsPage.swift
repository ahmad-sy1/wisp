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
    @State private var managingNS = false
    @State private var managingGmail = false
    @State private var confirmRemoveGmail = false

    var body: some View {
        SettingsPage(title: String(localized: "Integrations"),
                     subtitle: String(localized: "Only what you use is listed here. Add what you need."),
                     note: String(localized: "Keys and passwords are kept safely in your Mac's Keychain. Removing an integration disconnects it and deletes its key.")) {
            Menu {
                Button { managingGmail = true } label: { Text(verbatim: "Gmail") }
                    .disabled(mail.isConfigured)
                Button { SettingsNavigation.shared.page = .github } label: { Text(verbatim: "GitHub") }
                    .disabled(github.status != .disconnected)
                Button { managingNS = true } label: { Text(verbatim: "NS") }
                    .disabled(departure.hasNSKey)
            } label: {
                Label("Add integration", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 9).fill(prefs.accent.color))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(mail.isConfigured && github.status != .disconnected && departure.hasNSKey)
        } content: {
            SettingsGroup(header: String(localized: "In use")) {
                if mail.isConfigured {
                    IntegrationRow(name: "Gmail", color: Color(hex: 0xEA4335), status: gmailStatus,
                                   manage: { managingGmail = true },
                                   remove: { confirmRemoveGmail = true })
                }
                if github.status != .disconnected {
                    IntegrationRow(name: "GitHub", color: Color(hex: 0xF0F6FC), status: githubStatus,
                                   manage: { SettingsNavigation.shared.page = .github },
                                   remove: { github.disconnect() })
                }
                if departure.hasNSKey {
                    IntegrationRow(name: "NS", color: Theme.nsYellow, status: String(localized: "Key in your Keychain"),
                                   manage: { managingNS = true },
                                   remove: { departure.setNSKey(nil) })
                }
                IntegrationRow(name: String(localized: "Music"), color: Theme.ok, status: musicStatus,
                               manage: { SettingsNavigation.shared.page = .music },
                               remove: nil)
            }
        }
        .sheet(isPresented: $managingGmail) { GmailSheet(store: mail) }
        .sheet(isPresented: $managingNS) { NSKeySheet(store: departure) }
        .confirmationDialog(String(localized: "Remove Gmail?"), isPresented: $confirmRemoveGmail) {
            Button("Remove", role: .destructive) { mail.disconnect() }
        } message: {
            Text("wisp disconnects and deletes the app password from your Keychain.")
        }
    }

    private var gmailStatus: String {
        switch mail.status {
        case .notConfigured:     String(localized: "Not connected")
        case .connecting:        String(localized: "Connecting…")
        case .connected:         String(localized: "Connected · \(mail.address ?? "")")
        case .failed(let error): error
        }
    }

    private var githubStatus: String {
        switch github.status {
        case .disconnected:        String(localized: "Not connected")
        case .connecting:          String(localized: "Connecting…")
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

/// Connect Gmail, or change its app password: address + app password, kept in the
/// Keychain only.
private struct GmailSheet: View {
    @ObservedObject var store: MailStore
    @Environment(\.dismiss) private var dismiss
    @State private var address = MailStore.shared.address ?? ""
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: "Gmail").font(.headline)
            Form {
                TextField("Gmail address", text: $address, prompt: Text("name@gmail.com"))
                    .textContentType(.username)
                SecureField("App password", text: $password, prompt: Text("16 characters"))
            }
            .formStyle(.columns)
            Link("Create an app password…", destination: URL(string: "https://myaccount.google.com/apppasswords")!)
                .font(.caption)
            Text("wisp marks nothing as read and only changes your mailbox when you click Delete on new mail (it goes to the Gmail trash). Address and password are kept only in your Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Connect") {
                    store.connect(address: address, appPassword: password)
                    password = ""
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!address.contains("@") || password.replacingOccurrences(of: " ", with: "").count < 16)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

/// The key for NS's travel information: departures, tracks and delays. Keychain only.
private struct NSKeySheet: View {
    @ObservedObject var store: DepartureStore
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: "NS").font(.headline)
            SecureField("API key", text: $key, prompt: Text("Primary key"))
                .textFieldStyle(.roundedBorder)
            Link("Get a free key…", destination: URL(string: "https://apiportal.ns.nl")!)
                .font(.caption)
            Text("For lines, platforms and delays in the Departure tab. Without it, wisp shows a total time from Apple Maps. The key is kept only in your Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    store.setNSKey(key.trimmingCharacters(in: .whitespacesAndNewlines))
                    key = ""
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

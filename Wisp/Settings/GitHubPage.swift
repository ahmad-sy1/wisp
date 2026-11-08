import SwiftUI

/// Settings → GitHub (design page 5): the account, which repositories count, and what may
/// reach the notch. All GitHub notifications are set here; there is no separate tab for them.
struct GitHubPage: View {
    @ObservedObject var store: GitHubStore
    @State private var addingToken = false
    @State private var choosingRepositories = false

    var body: some View {
        SettingsPage(
            title: "GitHub",
            note: String(
                localized: "wisp checks more often while a run is going and calmly after that, to save your GitHub limit and battery.")
        ) {
            SettingsGroup(header: String(localized: "Account")) {
                account
                if store.isConnected {
                    SettingsRow(String(localized: "Repositories"), subtitle: String(localized: "Which repositories count")) {
                        Button(repositoryLabel) {
                            store.refreshRepositories()
                            choosingRepositories = true
                        }
                        .buttonStyle(.settings)
                    }
                }
            }

            SettingsGroup(header: String(localized: "Notifications in the notch")) {
                SettingsToggle(
                    String(localized: "CI failed"), subtitle: String(localized: "A red dot until you've looked at it"),
                    isOn: $store.notifyFailed)
                SettingsToggle(
                    String(localized: "CI passed"), subtitle: String(localized: "Only a short green flash"), isOn: $store.notifyPassed)
                SettingsToggle(
                    String(localized: "Review requested"), subtitle: String(localized: "A blue dot on the GitHub tab"),
                    isOn: $store.notifyReview)
                SettingsToggle(
                    String(localized: "New comments"), subtitle: String(localized: "On your own PRs"), isOn: $store.notifyComments)
                SettingsToggle(
                    String(localized: "Tick animation"), subtitle: String(localized: "The notch bounces briefly on a new event"),
                    isOn: $store.tickAnimation)
            }
        }
        .sheet(isPresented: $addingToken) { TokenSheet(store: store) }
        .sheet(isPresented: $choosingRepositories) { RepositorySheet(store: store) }
    }

    @ViewBuilder
    private var account: some View {
        switch store.status {
        case .connected(let login):
            SettingsRow(
                title: "@\(login)",
                subtitle: {
                    SettingsStatus(text: String(localized: "Connected"), color: Theme.ok)
                },
                trailing: {
                    Button("Disconnect") { store.disconnect() }
                        .buttonStyle(.settings)
                })
        case .connecting:
            SettingsRow(String(localized: "GitHub"), subtitle: String(localized: "Connecting…"))
        case .failed(let message):
            SettingsRow(String(localized: "GitHub"), subtitle: message) { connectButtons }
        case .disconnected:
            SettingsRow(String(localized: "GitHub"), subtitle: String(localized: "Not connected")) { connectButtons }
        }
    }

    private var connectButtons: some View {
        HStack(spacing: 8) {
            if store.hasCLI {
                Button("Use GitHub CLI login") { store.connectWithCLI() }
                    .buttonStyle(.settings)
            }
            Button("Add token…") { addingToken = true }
                .buttonStyle(.settings)
        }
    }

    private var repositoryLabel: String {
        let excluded = store.excludedRepositories.count
        guard excluded > 0 else {
            return store.repositories.isEmpty ? String(localized: "All") : String(localized: "All (\(store.repositories.count))")
        }
        return String(localized: "\(excluded) off")
    }
}

/// A personal access token, kept in the Keychain only.
private struct TokenSheet: View {
    @ObservedObject var store: GitHubStore
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: "GitHub").font(.headline)
            SecureField("Personal access token", text: $token, prompt: Text("Token"))
                .textFieldStyle(.roundedBorder)
            Link("Create a token…", destination: URL(string: "https://github.com/settings/tokens")!)
                .font(.caption)
            Text("wisp only reads: your pull requests, their checks and your contributions. The token is kept only in your Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Connect") {
                    store.connect(token: token)
                    token = ""
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

/// Which repositories count. All do, until you switch one off.
private struct RepositorySheet: View {
    @ObservedObject var store: GitHubStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Repositories").font(.headline)
            if store.repositories.isEmpty {
                Text("Looking for your repositories…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(store.repositories) { repository in
                            Toggle(
                                repository.fullName,
                                isOn: Binding(
                                    get: { !store.excludedRepositories.contains(repository.fullName) },
                                    set: { on in
                                        if on {
                                            store.excludedRepositories.remove(repository.fullName)
                                        } else {
                                            store.excludedRepositories.insert(repository.fullName)
                                        }
                                    }
                                )
                            )
                            .toggleStyle(.checkbox)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 280)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

import SwiftUI

/// Settings → Gmail: address + app password (stored in the Keychain only).
struct GmailSection: View {
    @ObservedObject var store: MailStore
    @State private var address = MailStore.shared.address ?? ""
    @State private var password = ""

    var body: some View {
        Section("Gmail") {
            if store.isConfigured {
                LabeledContent("Account") {
                    HStack(spacing: 8) {
                        Text(store.address ?? "").foregroundStyle(.secondary)
                        Button("Ontkoppelen") {
                            store.disconnect()
                            password = ""
                        }
                    }
                }
                LabeledContent("Status") {
                    Text(statusText).foregroundStyle(.secondary)
                }
            } else {
                TextField("Gmail-adres", text: $address, prompt: Text("naam@gmail.com"))
                    .textContentType(.username)
                SecureField("App-wachtwoord", text: $password, prompt: Text("16 tekens"))
                HStack {
                    Link("App-wachtwoord maken…", destination: URL(string: "https://myaccount.google.com/apppasswords")!)
                        .font(.caption)
                    Spacer()
                    Button("Verbinden") {
                        store.connect(address: address, appPassword: password)
                        password = ""
                    }
                    .disabled(!address.contains("@") || password.replacingOccurrences(of: " ", with: "").count < 16)
                }
                Text("Alleen lezen: wisp markeert niets als gelezen. Adres en wachtwoord staan alleen in je Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusText: String {
        switch store.status {
        case .notConfigured:     "Niet gekoppeld"
        case .connecting:        "Verbinden…"
        case .connected:         "Verbonden · \(store.unreadCount) ongelezen"
        case .failed(let error): error
        }
    }
}

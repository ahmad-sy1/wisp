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
                        Button("Disconnect") {
                            store.disconnect()
                            password = ""
                        }
                    }
                }
                LabeledContent("Status") {
                    Text(statusText).foregroundStyle(.secondary)
                }
                Toggle("Show new mail in the notch", isOn: $store.peekNewMail)
                Toggle("Unread count on the closed notch", isOn: $store.showUnreadOnNotch)
            } else {
                TextField("Gmail address", text: $address, prompt: Text("name@gmail.com"))
                    .textContentType(.username)
                SecureField("App password", text: $password, prompt: Text("16 characters"))
                HStack {
                    Link("Create an app password…", destination: URL(string: "https://myaccount.google.com/apppasswords")!)
                        .font(.caption)
                    Spacer()
                    Button("Connect") {
                        store.connect(address: address, appPassword: password)
                        password = ""
                    }
                    .disabled(!address.contains("@") || password.replacingOccurrences(of: " ", with: "").count < 16)
                }
                Text("wisp marks nothing as read and only changes your mailbox when you click Delete on new mail (it goes to the Gmail trash). Address and password are kept only in your Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusText: String {
        switch store.status {
        case .notConfigured:     String(localized: "Not connected")
        case .connecting:        String(localized: "Connecting…")
        case .connected:         String(localized: "Connected · \(store.unreadCount) unread")
        case .failed(let error): error
        }
    }
}

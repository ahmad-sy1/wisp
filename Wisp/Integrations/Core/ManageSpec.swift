import Foundation

struct ManageField: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let placeholder: String
    var isSecret = false
}

/// What the one Manage window (boards 10.3.2, 10.3.3) needs to know about a service.
/// Only the fields differ per service; the layout never does.
struct ManageSpec: Equatable, Sendable {
    let info: IntegrationInfo
    let blurb: String
    let checking: String
    let fields: [ManageField]
    let helpTitle: String
    let helpURL: String
    let helpText: String
    let privacy: String

    func canConnect(_ values: [String: String]) -> Bool {
        switch info.id {
        case .gmail:
            let address = (values[ManageSpec.addressField] ?? "").trimmingCharacters(in: .whitespaces)
            let password = (values[ManageSpec.passwordField] ?? "").replacingOccurrences(of: " ", with: "")
            return ManageSpec.looksLikeAddress(address) && password.count >= 16
        case .ns:
            return !(values[ManageSpec.keyField] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .github:
            return false
        }
    }

    static let addressField = "address"
    static let passwordField = "password"
    static let keyField = "key"

    private static func looksLikeAddress(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !text.contains(" ")
    }
}

extension IntegrationCatalog {
    static func info(_ id: IntegrationID) -> IntegrationInfo? {
        all.first { $0.id == id }
    }

    /// `nil` for a service that is set up on its own page (GitHub, for now).
    static func manageSpec(for id: IntegrationID) -> ManageSpec? {
        guard let info = info(id) else { return nil }
        switch id {
        case .gmail:
            return ManageSpec(
                info: info,
                blurb: String(localized: "Inbox, unread count and new-mail alerts in your notch."),
                checking: String(localized: "Signing in to Gmail…"),
                fields: [
                    ManageField(
                        id: ManageSpec.addressField, label: String(localized: "Email address"), placeholder: "you@gmail.com"),
                    ManageField(
                        id: ManageSpec.passwordField, label: String(localized: "App password"),
                        placeholder: String(localized: "16 characters"), isSecret: true),
                ],
                helpTitle: String(localized: "Create an app password"),
                helpURL: "https://myaccount.google.com/apppasswords",
                helpText: String(localized: "myaccount.google.com/apppasswords · needs 2-step verification. Paste it without spaces."),
                privacy: String(localized: "Stored in your Mac's Keychain. wisp only talks to Google."))
        case .ns:
            return ManageSpec(
                info: info,
                blurb: String(localized: "Train departures and delays for the departure assistant."),
                checking: String(localized: "Asking NS for the next departure…"),
                fields: [
                    ManageField(
                        id: ManageSpec.keyField, label: String(localized: "API key"),
                        placeholder: String(localized: "Primary key from the NS API portal"), isSecret: true)
                ],
                helpTitle: String(localized: "Get a free key at apiportal.ns.nl"),
                helpURL: "https://apiportal.ns.nl",
                helpText: String(localized: "Subscribe to the “Ns-App” product and copy the primary key."),
                privacy: String(localized: "Stored in your Mac's Keychain. wisp only talks to NS."))
        case .github:
            return nil
        }
    }
}

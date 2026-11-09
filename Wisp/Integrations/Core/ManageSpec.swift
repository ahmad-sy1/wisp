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
    let rejectedMessage: String
    let unreachableMessage: String
    /// The field a failed check points at.
    let failureField: String

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
                privacy: String(localized: "Stored in your Mac's Keychain. wisp only talks to Google."),
                rejectedMessage: String(
                    localized: "Google rejected this app password. Check that 2-step verification is on and paste it again."),
                unreachableMessage: String(localized: "Couldn't reach Gmail. Check your connection and try again."),
                failureField: ManageSpec.passwordField)
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
                privacy: String(localized: "Stored in your Mac's Keychain. wisp only talks to NS."),
                rejectedMessage: String(
                    localized: "NS rejected this key. Copy the primary key of your subscription, not the secondary one."),
                unreachableMessage: String(localized: "Couldn't reach NS. Check your connection and try again."),
                failureField: ManageSpec.keyField)
        case .github:
            return nil
        }
    }
}

/// Where an integration stands.
enum IntegrationStatus: Equatable, Sendable {
    case notConnected, checking, failed, connected

    var title: String {
        switch self {
        case .notConnected: String(localized: "Not connected")
        case .checking: String(localized: "Checking")
        case .failed: String(localized: "Couldn't connect")
        case .connected: String(localized: "Connected")
        }
    }
}

/// What the window itself is doing.
enum ManagePhase: Equatable, Sendable {
    case idle, checking
    case failed(message: String, field: String)
}

/// What is stored for a service and how its connection is doing.
struct ManageAccount: Equatable, Sendable {
    enum Health: Equatable, Sendable {
        case healthy, connecting
        case failed(String)
    }

    var isConnected = false
    var health = Health.healthy
    /// The line under the name while connected.
    var summary = ""
    var address: String?
}

extension ManageSpec {
    func status(phase: ManagePhase, account: ManageAccount) -> IntegrationStatus {
        switch phase {
        case .checking: return .checking
        case .failed: return .failed
        case .idle: break
        }
        guard account.isConnected else { return .notConnected }
        switch account.health {
        case .healthy: return .connected
        case .connecting: return .checking
        case .failed: return .failed
        }
    }

    func summary(phase: ManagePhase, account: ManageAccount) -> String {
        if phase == .checking { return checking }
        guard account.isConnected else { return blurb }
        if case .failed(let message) = account.health { return message }
        return account.summary
    }

    /// What the window shows after the service has answered.
    func phase(after check: CredentialCheck) -> ManagePhase {
        switch check {
        case .accepted: .idle
        case .rejected: .failed(message: rejectedMessage, field: failureField)
        case .unreachable: .failed(message: unreachableMessage, field: failureField)
        }
    }
}

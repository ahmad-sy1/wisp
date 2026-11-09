import Foundation

/// Reads how each integration is doing from its own store.
@MainActor
enum IntegrationConnections {
    static func current(
        mail: MailStore = .shared, github: GitHubStore = .shared, departure: DepartureStore = .shared
    ) -> [IntegrationID: IntegrationConnection] {
        var result: [IntegrationID: IntegrationConnection] = [:]
        if mail.isConfigured {
            switch mail.status {
            case .connected: result[.gmail] = .connected(String(localized: "Connected · \(mail.address ?? "")"))
            case .failed(let message): result[.gmail] = .problem(message)
            case .connecting, .notConfigured: result[.gmail] = .connecting
            }
        }
        switch github.status {
        case .disconnected: break
        case .connecting: result[.github] = .connecting
        case .connected(let login): result[.github] = .connected(String(localized: "Connected · @\(login)"))
        case .failed(let message): result[.github] = .problem(message)
        }
        if departure.hasNSKey { result[.ns] = .connected(String(localized: "Connected")) }
        #if DEBUG
            // `-pretendNotConnected '("ns")'` for snapshots of a row that still needs setting up.
            for name in UserDefaults.standard.stringArray(forKey: "pretendNotConnected") ?? [] {
                if let id = IntegrationID(rawValue: name) { result[id] = nil }
            }
        #endif
        return result
    }
}

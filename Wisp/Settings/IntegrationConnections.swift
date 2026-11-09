import Foundation

/// Reads how each integration is doing from its own store.
@MainActor
enum IntegrationConnections {
    static func current(
        mail: MailStore = .shared, github: GitHubStore = .shared, departure: DepartureStore = .shared
    ) -> [IntegrationID: IntegrationConnection] {
        var result: [IntegrationID: IntegrationConnection] = [:]
        var mailProblem: String?
        if case .failed(let message) = mail.status { mailProblem = message }
        result[.gmail] = .make(
            isStored: mail.isConfigured, isReady: mail.status == .connected, problem: mailProblem,
            detail: String(localized: "Connected · \(mail.address ?? "")"))

        var login = ""
        var githubReady = false
        var githubProblem: String?
        switch github.status {
        case .connected(let name):
            login = name
            githubReady = true
        case .failed(let message): githubProblem = message
        case .connecting, .disconnected: break
        }
        result[.github] = .make(
            isStored: github.status != .disconnected, isReady: githubReady, problem: githubProblem,
            detail: String(localized: "Connected · @\(login)"))

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

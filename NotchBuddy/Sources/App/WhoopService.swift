import AppKit
import Foundation

/// WHOOP integration: OAuth 2.0 (authorization code + refresh token) and polling of
/// the latest recovery, cycle (strain) and sleep from the WHOOP Developer API v2.
/// Client ID/secret and tokens live in the Keychain only.
@MainActor
final class WhoopService {
    static let shared = WhoopService()
    private init() {}

    static let redirectURI = "coucou://whoop/callback"
    private static let authURL  = "https://api.prod.whoop.com/oauth/oauth2/auth"
    private static let tokenURL = URL(string: "https://api.prod.whoop.com/oauth/oauth2/token")!
    private static let apiBase  = "https://api.prod.whoop.com/developer/v2"
    private static let scopes   = "offline read:recovery read:cycles read:sleep read:profile"

    private enum Key {
        static let clientId     = "whoop-client-id"
        static let clientSecret = "whoop-client-secret"
        static let access       = "whoop-access-token"
        static let refresh      = "whoop-refresh-token"
        static let expiry       = "whoop-token-expiry"
    }

    private var pendingState: String?
    private var pollTask: Task<Void, Never>?
    private var polling = false

    var isConnected: Bool { KeychainStore.shared.get(Key.refresh) != nil }

    // MARK: - Polling

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(900))
            }
        }
    }

    func pollNow() { Task { await poll() } }

    // MARK: - OAuth

    /// Opens the WHOOP consent page in the browser. The answer comes back via `coucou://whoop/callback`.
    func connect() {
        guard let clientId = KeychainStore.shared.get(Key.clientId) else {
            AppState.shared.whoopError = "Client ID not configured"
            return
        }
        // WHOOP requires an 8-character state.
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let state = String((0..<8).map { _ in alphabet.randomElement()! })
        pendingState = state

        var comps = URLComponents(string: Self.authURL)!
        comps.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id",     value: clientId),
            .init(name: "redirect_uri",  value: Self.redirectURI),
            .init(name: "scope",         value: Self.scopes),
            .init(name: "state",         value: state),
        ]
        if let url = comps.url { NSWorkspace.shared.open(url) }
    }

    func disconnect() {
        for k in [Key.access, Key.refresh, Key.expiry] { KeychainStore.shared.remove(k) }
        AppState.shared.whoop = nil
        AppState.shared.whoopLoaded = false
        AppState.shared.whoopError = nil
    }

    /// Handles `coucou://whoop/callback?code=…&state=…`.
    func handleCallback(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func item(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let err = item("error") {
            AppState.shared.whoopError = "WHOOP: \(item("error_description") ?? err)"
            return
        }
        guard let state = item("state"), state == pendingState, let code = item("code") else {
            AppState.shared.whoopError = "WHOOP login failed (state mismatch)"
            return
        }
        pendingState = nil
        Task {
            do {
                try await requestToken(["grant_type": "authorization_code", "code": code,
                                        "redirect_uri": Self.redirectURI])
                AppState.shared.whoopError = nil
                await poll()
            } catch {
                AppState.shared.whoopError = error.localizedDescription
            }
        }
    }

    private func requestToken(_ params: [String: String]) async throws {
        guard let clientId = KeychainStore.shared.get(Key.clientId),
              let secret = KeychainStore.shared.get(Key.clientSecret) else {
            throw WhoopError.message("Client ID / secret not configured")
        }
        var all = params
        all["client_id"] = clientId
        all["client_secret"] = secret

        var req = URLRequest(url: Self.tokenURL, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.formEncode(all).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else {
            if code == 400 || code == 401 { throw WhoopError.reauth }
            throw WhoopError.message("Token error \(code)")
        }
        let expiresIn = (json["expires_in"] as? Double) ?? 3600
        KeychainStore.shared.set(Key.access, value: access)
        KeychainStore.shared.set(Key.expiry, value: String(Date().timeIntervalSince1970 + expiresIn))
        // Refresh tokens rotate: always store the newest one.
        if let refresh = json["refresh_token"] as? String {
            KeychainStore.shared.set(Key.refresh, value: refresh)
        }
    }

    private func validAccessToken() async throws -> String {
        let expiry = Double(KeychainStore.shared.get(Key.expiry) ?? "") ?? 0
        if let access = KeychainStore.shared.get(Key.access), Date().timeIntervalSince1970 < expiry - 60 {
            return access
        }
        guard let refresh = KeychainStore.shared.get(Key.refresh) else { throw WhoopError.reauth }
        try await requestToken(["grant_type": "refresh_token", "refresh_token": refresh, "scope": "offline"])
        guard let access = KeychainStore.shared.get(Key.access) else { throw WhoopError.reauth }
        return access
    }

    // MARK: - Data

    private func poll() async {
        guard isConnected, !polling else { return }
        polling = true
        defer { polling = false }
        do {
            let token = try await validAccessToken()
            let recovery = try await get("/recovery?limit=1", token: token).first?["score"] as? [String: Any]
            let cycle    = try await get("/cycle?limit=1", token: token).first?["score"] as? [String: Any]
            let sleep    = try await get("/activity/sleep?limit=5", token: token)
                .first { ($0["nap"] as? Bool) != true }?["score"] as? [String: Any]

            var sleepDuration: TimeInterval? = nil
            if let stages = sleep?["stage_summary"] as? [String: Any],
               let inBed = Self.number(stages["total_in_bed_time_milli"]),
               let awake = Self.number(stages["total_awake_time_milli"]) {
                sleepDuration = (inBed - awake) / 1000
            }

            AppState.shared.whoop = WhoopSnapshot(
                recovery: Self.number(recovery?["recovery_score"]).map { Int($0.rounded()) },
                hrv: Self.number(recovery?["hrv_rmssd_milli"]),
                restingHR: Self.number(recovery?["resting_heart_rate"]).map { Int($0.rounded()) },
                strain: Self.number(cycle?["strain"]),
                sleepPerformance: Self.number(sleep?["sleep_performance_percentage"]).map { Int($0.rounded()) },
                sleepDuration: sleepDuration,
                updatedAt: Date()
            )
            AppState.shared.whoopLoaded = true
            AppState.shared.whoopError = nil
            appendAppLog("whoop.log", "poll ok: \(AppState.shared.whoop?.chatContext ?? "")")
        } catch WhoopError.reauth {
            AppState.shared.whoopError = "Session expired — reconnect in Settings"
            appendAppLog("whoop.log", "poll: session expired")
        } catch {
            AppState.shared.whoopError = (error as? WhoopError)?.text ?? error.localizedDescription
            appendAppLog("whoop.log", "poll failed: \(AppState.shared.whoopError ?? "")")
        }
    }

    private func get(_ path: String, token: String) async throws -> [[String: Any]] {
        guard let url = URL(string: Self.apiBase + path) else { return [] }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw WhoopError.reauth }
        guard code == 200 else { throw WhoopError.message("API error \(code)") }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["records"] as? [[String: Any]] ?? []
    }

    // MARK: - Helpers

    private static func number(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }

    private static func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)"
        }.joined(separator: "&")
    }

    private enum WhoopError: Error {
        case reauth
        case message(String)
        var text: String {
            switch self {
            case .reauth: return "Session expired — reconnect in Settings"
            case .message(let m): return m
            }
        }
    }
}

// MARK: - Model

struct WhoopSnapshot: Equatable {
    let recovery: Int?
    let hrv: Double?
    let restingHR: Int?
    let strain: Double?
    let sleepPerformance: Int?
    let sleepDuration: TimeInterval?
    let updatedAt: Date

    /// WHOOP's own recovery bands: green ≥ 67, yellow 34–66, red ≤ 33.
    var recoveryColor: String {
        guard let r = recovery else { return "#6B7079" }
        if r >= 67 { return "#22C55E" }
        if r >= 34 { return "#F5A524" }
        return "#F4505E"
    }

    var sleepLabel: String {
        var parts: [String] = []
        if let d = sleepDuration {
            let mins = Int(d / 60)
            parts.append("\(mins / 60)h\(String(format: "%02d", mins % 60))")
        }
        if let p = sleepPerformance { parts.append("\(p)%") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    /// One-line summary handed to Mochi's chat so it can answer health questions.
    var chatContext: String {
        var parts: [String] = []
        if let r = recovery { parts.append("recovery \(r)%") }
        if let h = hrv { parts.append("HRV \(Int(h.rounded())) ms") }
        if let rhr = restingHR { parts.append("resting HR \(rhr) bpm") }
        if let s = strain { parts.append("day strain \(String(format: "%.1f", s))") }
        if sleepDuration != nil || sleepPerformance != nil { parts.append("last sleep \(sleepLabel)") }
        return parts.joined(separator: ", ")
    }
}

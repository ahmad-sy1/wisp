import Foundation

/// The OAuth 2.0 steps of WHOOP's sign-in, kept free of networking so they can be tested.
///
/// WHOOP gives every developer app a client ID and a secret, and the secret can't ship in a
/// public app, so each person registers wisp once and enters both in the Manage window.
enum WhoopOAuth {
    static let authorizeURL = URL(string: "https://api.prod.whoop.com/oauth/oauth2/auth")!
    static let tokenURL = URL(string: "https://api.prod.whoop.com/oauth/oauth2/token")!
    /// Registered as the redirect URL of the developer app; `wisp://` is in Info.plist.
    static let redirectURI = "wisp://oauth/whoop"
    /// `offline` brings a refresh token, so nobody signs in again every hour.
    static let scopes = ["read:recovery", "read:cycles", "read:sleep", "read:profile", "offline"]

    struct Client: Equatable, Sendable {
        let id: String
        let secret: String
    }

    /// What WHOOP hands out; `refresh` changes on every refresh.
    struct Tokens: Codable, Equatable, Sendable {
        let access: String
        let refresh: String
        let expires: Date

        /// A minute early, so a request never starts with a token that runs out on the way.
        func isFresh(at now: Date) -> Bool { expires.timeIntervalSince(now) > 60 }
    }

    enum Callback: Equatable, Sendable {
        case code(String)
        case denied(String)
    }

    /// WHOOP wants a state of eight characters.
    static func makeState() -> String {
        let alphabet = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<8).map { _ in alphabet.randomElement()! })
    }

    static func authorizationURL(client: Client, state: String) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: client.id),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    /// `nil` for a URL that isn't this sign-in's answer (another path, or a stale state).
    static func parseCallback(_ url: URL, state: String) -> Callback? {
        guard url.scheme == "wisp", url.host == "oauth", url.path == "/whoop",
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
            items.first(where: { $0.name == "state" })?.value == state
        else { return nil }
        if let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty { return .code(code) }
        return .denied(items.first(where: { $0.name == "error" })?.value ?? "unknown")
    }

    static func codeRequest(_ code: String, client: Client) -> HTTPRequest {
        form([
            "grant_type": "authorization_code", "code": code, "redirect_uri": redirectURI,
            "client_id": client.id, "client_secret": client.secret,
        ])
    }

    static func refreshRequest(_ refresh: String, client: Client) -> HTTPRequest {
        form([
            "grant_type": "refresh_token", "refresh_token": refresh, "scope": "offline",
            "client_id": client.id, "client_secret": client.secret,
        ])
    }

    static func parseTokens(_ data: Data, now: Date) throws -> Tokens {
        struct Answer: Decodable {
            let access_token: String
            let refresh_token: String
            let expires_in: Double
        }
        let answer = try JSONDecoder().decode(Answer.self, from: data)
        return Tokens(access: answer.access_token, refresh: answer.refresh_token, expires: now.addingTimeInterval(answer.expires_in))
    }

    private static func form(_ fields: [String: String]) -> HTTPRequest {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
        return HTTPRequest(
            url: tokenURL, method: "POST",
            headers: ["Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"],
            body: Data(body.utf8))
    }
}

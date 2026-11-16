import Foundation

enum WhoopError: Error, Equatable {
    /// WHOOP no longer accepts the refresh token (revoked, or the secret changed): sign in again.
    case signedOut
    /// The client ID or secret was refused.
    case rejected
    case unreachable
}

/// Talks to WHOOP's v2 API. Refreshes the access token when it runs out; WHOOP hands out a
/// new refresh token each time and the old one stops working, so refreshes never overlap
/// (an actor runs one at a time) and every new pair goes to `save` straight away.
actor WhoopClient {
    static let apiBase = URL(string: "https://api.prod.whoop.com/developer/v2/")!

    private let transport: any HTTPTransport
    private let client: WhoopOAuth.Client
    private var tokens: WhoopOAuth.Tokens
    private let save: @Sendable (WhoopOAuth.Tokens) -> Void
    private let now: @Sendable () -> Date

    init(
        transport: any HTTPTransport, client: WhoopOAuth.Client, tokens: WhoopOAuth.Tokens,
        save: @escaping @Sendable (WhoopOAuth.Tokens) -> Void,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.transport = transport
        self.client = client
        self.tokens = tokens
        self.save = save
        self.now = now
    }

    /// Trades the code from the browser for the first tokens.
    static func exchange(code: String, client: WhoopOAuth.Client, transport: any HTTPTransport) async throws
        -> WhoopOAuth.Tokens
    {
        let response: HTTPResponse
        do {
            response = try await transport.send(WhoopOAuth.codeRequest(code, client: client))
        } catch {
            throw WhoopError.unreachable
        }
        switch response.status {
        case 200..<300:
            guard let tokens = try? WhoopOAuth.parseTokens(response.body, now: Date()) else { throw WhoopError.unreachable }
            return tokens
        case 400, 401, 403: throw WhoopError.rejected
        default: throw WhoopError.unreachable
        }
    }

    func today() async throws -> WhoopToday {
        async let recovery = get("recovery?limit=7")
        async let sleep = get("activity/sleep?limit=5")
        async let cycle = get("cycle?limit=1")
        return WhoopToday(
            recovery: try WhoopParser.recovery(try await recovery),
            sleep: try WhoopParser.sleep(try await sleep),
            strain: try WhoopParser.strain(try await cycle))
    }

    func firstName() async throws -> String {
        try WhoopParser.firstName(try await get("user/profile/basic"))
    }

    /// Tells WHOOP that wisp lets go; best effort, the tokens are deleted either way.
    func revoke() async {
        guard let token = try? await accessToken(),
            let url = URL(string: "user/access", relativeTo: Self.apiBase)
        else { return }
        _ = try? await transport.send(HTTPRequest(url: url, method: "DELETE", headers: ["Authorization": "Bearer \(token)"]))
    }

    // MARK: - Requests

    private func get(_ path: String) async throws -> Data {
        guard let url = URL(string: path, relativeTo: Self.apiBase) else { throw WhoopError.unreachable }
        var response = try await send(url, token: try await accessToken())
        if response.status == 401 {
            // Revoked early, or the clock is off: one refresh, then give up.
            try await refresh()
            response = try await send(url, token: tokens.access)
        }
        switch response.status {
        case 200..<300: return response.body
        case 401: throw WhoopError.signedOut
        default: throw WhoopError.unreachable
        }
    }

    private func send(_ url: URL, token: String) async throws -> HTTPResponse {
        do {
            return try await transport.send(
                HTTPRequest(url: url, headers: ["Authorization": "Bearer \(token)", "Accept": "application/json"]))
        } catch {
            throw WhoopError.unreachable
        }
    }

    private var refreshing: Task<WhoopOAuth.Tokens, Error>?

    private func accessToken() async throws -> String {
        if let refreshing { return try await refreshing.value.access }
        if tokens.isFresh(at: now()) { return tokens.access }
        try await refresh()
        return tokens.access
    }

    /// Requests that need a token while one refresh is underway wait for it.
    private func refresh() async throws {
        if let refreshing {
            _ = try await refreshing.value
            return
        }
        let request = WhoopOAuth.refreshRequest(tokens.refresh, client: client)
        let transport = transport
        let now = now
        let task = Task<WhoopOAuth.Tokens, Error> {
            let response: HTTPResponse
            do {
                response = try await transport.send(request)
            } catch {
                throw WhoopError.unreachable
            }
            switch response.status {
            case 200..<300:
                guard let tokens = try? WhoopOAuth.parseTokens(response.body, now: now()) else {
                    throw WhoopError.unreachable
                }
                return tokens
            case 400, 401, 403: throw WhoopError.signedOut
            default: throw WhoopError.unreachable
            }
        }
        refreshing = task
        defer { refreshing = nil }
        tokens = try await task.value
        save(tokens)
    }
}

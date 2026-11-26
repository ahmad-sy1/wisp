import AppKit
import Combine

/// WHOOP's recovery, sleep and strain, asked for every 30 minutes while connected.
///
/// The client ID and secret of the person's own developer app, and the tokens, live in the
/// Keychain. Signing in goes through the browser and comes back on `wisp://oauth/whoop`.
@MainActor
final class WhoopStore: ObservableObject {
    static let shared = WhoopStore()

    enum Status: Equatable {
        case notConnected
        /// Tokens are stored; the first answer hasn't come yet.
        case connecting
        case connected
        /// WHOOP stopped accepting the tokens.
        case signedOut(since: Date)
    }

    @Published private(set) var status: Status = .notConnected
    /// `nil` until WHOOP has answered once; empty when it has nothing scored yet.
    @Published private(set) var today: WhoopToday?
    @Published private(set) var lastSync: Date?
    @Published private(set) var firstName: String?
    @Published private(set) var isSyncing = false

    /// Something is stored, so it counts as connected (also while signed out).
    var hasConnection: Bool { status != .notConnected }

    var storedClientID: String? { Keychain.get(Key.clientID) }

    static let interval: TimeInterval = 30 * 60
    static let appURL = URL(string: "https://app.whoop.com")!

    private let transport = URLSessionTransport()
    private var client: WhoopClient?
    private var polling: Task<Void, Never>?
    private var pendingSignIn: (state: String, resume: (WhoopOAuth.Callback?) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var isDemo = false

    private enum Key {
        static let clientID = "whoop-client-id"
        static let clientSecret = "whoop-client-secret"
        static let tokens = "whoop-tokens"
        static let signedOutSince = "whoopSignedOutSince"
    }

    func start() {
        #if DEBUG
            // `-whoopDemo data|empty|signedOut` for snapshots without an account.
            if let demo = UserDefaults.standard.string(forKey: "whoopDemo") {
                startDemo(demo)
                return
            }
        #endif
        let wake = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncIfStale() }
        }
        observers.append(wake)
        resume()
    }

    /// Picks up what the Keychain holds.
    private func resume() {
        guard let client = storedClient(), let data = Keychain.get(Key.tokens)?.data(using: .utf8),
            let tokens = try? JSONDecoder().decode(WhoopOAuth.Tokens.self, from: data)
        else {
            status = .notConnected
            return
        }
        self.client = makeClient(client, tokens: tokens)
        if let since = UserDefaults.standard.object(forKey: Key.signedOutSince) as? Date {
            status = .signedOut(since: since)
            return
        }
        status = .connecting
        startPolling()
    }

    // MARK: - Signing in

    /// Opens WHOOP's sign-in in the browser and waits for it to come back. Nothing is stored
    /// unless WHOOP hands out tokens.
    func signIn(clientID: String, secret: String) async -> CredentialCheck {
        let client = WhoopOAuth.Client(id: clientID, secret: secret)
        let state = WhoopOAuth.makeState()
        NSWorkspace.shared.open(WhoopOAuth.authorizationURL(client: client, state: state))
        guard case .code(let code) = await waitForCallback(state: state) else { return .rejected }
        do {
            let tokens = try await WhoopClient.exchange(code: code, client: client, transport: transport)
            guard !Task.isCancelled else { return .rejected }
            if status == .notConnected { Preferences.shared.placeTab(.whoop, after: .github) }
            Keychain.set(clientID, for: Key.clientID)
            Keychain.set(secret, for: Key.clientSecret)
            store(tokens)
            UserDefaults.standard.removeObject(forKey: Key.signedOutSince)
            self.client = makeClient(client, tokens: tokens)
            // Possibly another account than before.
            firstName = nil
            status = .connecting
            startPolling()
            return .accepted
        } catch WhoopError.rejected {
            return .rejected
        } catch {
            return .unreachable
        }
    }

    /// Signs in again with the stored client, after WHOOP signed wisp out.
    func reconnect() {
        guard let client = storedClient() else { return }
        Task { _ = await signIn(clientID: client.id, secret: client.secret) }
    }

    /// The browser's answer. `false` for a URL that isn't the sign-in being waited for.
    func handle(_ url: URL) -> Bool {
        guard let pending = pendingSignIn, let callback = WhoopOAuth.parseCallback(url, state: pending.state) else {
            return false
        }
        pendingSignIn = nil
        pending.resume(callback)
        NSApp.activate()
        return true
    }

    /// Gives up after five minutes, or when the Manage window closes (the task is cancelled).
    private func waitForCallback(state: String) async -> WhoopOAuth.Callback? {
        pendingSignIn?.resume(nil)
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(300))
            guard !Task.isCancelled else { return }
            self?.cancelSignIn(state: state)
        }
        defer { timeout.cancel() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pendingSignIn = (state, { continuation.resume(returning: $0) })
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelSignIn(state: state) }
        }
    }

    private func cancelSignIn(state: String) {
        guard let pending = pendingSignIn, pending.state == state else { return }
        pendingSignIn = nil
        pending.resume(nil)
    }

    func disconnect() {
        polling?.cancel()
        polling = nil
        if let client { Task { await client.revoke() } }
        client = nil
        for key in [Key.clientID, Key.clientSecret, Key.tokens] { Keychain.remove(key) }
        UserDefaults.standard.removeObject(forKey: Key.signedOutSince)
        status = .notConnected
        today = nil
        lastSync = nil
        firstName = nil
    }

    // MARK: - Syncing

    func refresh() {
        guard !isDemo, client != nil, !isSyncing else { return }
        Task { await sync() }
    }

    func syncIfStale() {
        guard status == .connected || status == .connecting else { return }
        if let lastSync, Date().timeIntervalSince(lastSync) < Self.interval { return }
        refresh()
    }

    private func startPolling() {
        polling?.cancel()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sync()
                try? await Task.sleep(for: .seconds(Self.interval))
            }
        }
    }

    private func sync() async {
        guard let client, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let today = try await client.today()
            let name = firstName == nil ? try? await client.firstName() : nil
            // Disconnected or signed in again while this round ran: its answers are stale.
            guard self.client === client else { return }
            if let name { firstName = name }
            self.today = today
            lastSync = Date()
            status = .connected
        } catch WhoopError.signedOut {
            guard self.client === client else { return }
            let since = Date()
            UserDefaults.standard.set(since, forKey: Key.signedOutSince)
            polling?.cancel()
            status = .signedOut(since: since)
        } catch {
            // Offline or WHOOP is down: keep what is shown and try again next time.
        }
    }

    // MARK: - Keychain

    private func storedClient() -> WhoopOAuth.Client? {
        guard let id = Keychain.get(Key.clientID), let secret = Keychain.get(Key.clientSecret) else { return nil }
        return WhoopOAuth.Client(id: id, secret: secret)
    }

    private func makeClient(_ client: WhoopOAuth.Client, tokens: WhoopOAuth.Tokens) -> WhoopClient {
        WhoopClient(transport: transport, client: client, tokens: tokens) { tokens in
            // A refresh that finishes after Disconnect must not bring the tokens back.
            Task { @MainActor in
                guard WhoopStore.shared.hasConnection else { return }
                WhoopStore.store(tokens)
            }
        }
    }

    private func store(_ tokens: WhoopOAuth.Tokens) { Self.store(tokens) }

    private static func store(_ tokens: WhoopOAuth.Tokens) {
        guard let data = try? JSONEncoder().encode(tokens), let text = String(data: data, encoding: .utf8) else { return }
        Keychain.set(text, for: Key.tokens)
    }

    // MARK: - Demo

    #if DEBUG
        private func startDemo(_ demo: String) {
            isDemo = true
            firstName = "Ahmad"
            lastSync = Date().addingTimeInterval(-5 * 60)
            switch demo {
            case "empty":
                status = .connected
                today = WhoopToday()
            case "signedOut":
                var calendar = Calendar.current
                calendar.timeZone = .current
                let since = calendar.date(bySettingHour: 9, minute: 12, second: 0, of: Date()) ?? Date()
                status = .signedOut(since: since)
            default:
                status = .connected
                today = WhoopToday(
                    recovery: .init(score: 68, hrv: 62, restingHeartRate: 54, recent: [52, 71, 40, 58, 74, 49, 68]),
                    sleep: .init(deep: 6480, light: 13320, rem: 6120, awake: 1800, performance: 91),
                    strain: .init(score: 9.4, kilocalories: 1840))
            }
        }
    #endif
}

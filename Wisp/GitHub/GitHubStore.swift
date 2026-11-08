import AppKit
import Combine

/// The CI & PR radar: asks GitHub for your open pull requests while you are connected.
///
/// There is one pending wake-up at a time, whose delay comes from `PollSchedule`. Asleep or
/// with the screen locked nothing is scheduled; not connected, nothing exists at all.
@MainActor
final class GitHubStore: ObservableObject {
    static let shared = GitHubStore()

    enum Status: Equatable {
        case disconnected
        case connecting
        case connected(login: String)
        case failed(String)
    }

    @Published private(set) var status: Status = .disconnected
    @Published private(set) var snapshot = RadarSnapshot()
    @Published private(set) var compact: RadarCompact = .none
    @Published private(set) var stats: ContributionStats?
    @Published private(set) var repositories: [GitHubRepository] = []
    @Published private(set) var seen: RadarSeen {
        didSet {
            if let data = try? JSONEncoder().encode(seen) { defaults.set(data, forKey: Key.seen) }
            updateCompact()
        }
    }

    /// Repositories that don't count (Settings → GitHub). Everything else does.
    @Published var excludedRepositories: Set<String> {
        didSet {
            defaults.set(Array(excludedRepositories), forKey: Key.excluded)
            pollSoon()
        }
    }

    @Published var notifyFailed: Bool { didSet { saveNotifications(notifyFailed, Key.failed) } }
    @Published var notifyPassed: Bool { didSet { saveNotifications(notifyPassed, Key.passed) } }
    @Published var notifyReview: Bool { didSet { saveNotifications(notifyReview, Key.review) } }
    @Published var notifyComments: Bool { didSet { saveNotifications(notifyComments, Key.comments) } }
    @Published var tickAnimation: Bool { didSet { saveNotifications(tickAnimation, Key.tick) } }

    /// Something new, once per event.
    var onEvent: (RadarEvent) -> Void = { _ in }

    var isConnected: Bool {
        if case .connected = status { true } else { false }
    }

    var login: String? {
        if case .connected(let login) = status { login } else { nil }
    }

    private let defaults = UserDefaults.standard
    private var service: (any GitHubService)?
    private var sync: RadarSync?
    private var wake: DispatchWorkItem?
    private var polling: Task<Void, Never>?
    private var failures = 0
    private var blockedUntil: Date?
    private var lastChange: Date?
    private var asleep = false
    private var observers: [NSObjectProtocol] = []
    private var tabVisible = false
    private var statsFetched: Date?

    private static let tokenAccount = "github-token"
    private static let statsMaxAge: TimeInterval = 30 * 60
    private static let activeWindow: TimeInterval = 5 * 60

    private enum Key {
        static let seen = "githubSeen"
        static let excluded = "githubExcludedRepositories"
        static let failed = "githubNotifyFailed"
        static let passed = "githubNotifyPassed"
        static let review = "githubNotifyReview"
        static let comments = "githubNotifyComments"
        static let tick = "githubTickAnimation"
    }

    private init() {
        seen = defaults.data(forKey: Key.seen).flatMap { try? JSONDecoder().decode(RadarSeen.self, from: $0) } ?? RadarSeen()
        excludedRepositories = Set(defaults.stringArray(forKey: Key.excluded) ?? [])
        notifyFailed = defaults.object(forKey: Key.failed) as? Bool ?? true
        notifyPassed = defaults.object(forKey: Key.passed) as? Bool ?? true
        notifyReview = defaults.object(forKey: Key.review) as? Bool ?? true
        notifyComments = defaults.object(forKey: Key.comments) as? Bool ?? true
        tickAnimation = defaults.object(forKey: Key.tick) as? Bool ?? true
    }

    // MARK: - Connecting

    /// At launch: goes on with the key in the Keychain, if there is one.
    func start() {
        observeSleep()
        #if DEBUG
        // `-githubDemo YES` shows made-up data, for snapshots and without an account.
        if UserDefaults.standard.bool(forKey: "githubDemo") { return startDemo() }
        // `-githubFromCLI YES` borrows the `gh` login for this run only; nothing is saved.
        if UserDefaults.standard.bool(forKey: "githubFromCLI") {
            if let token = Self.tokenFromCLI() { begin(with: GitHubClient(token: token)) }
            return
        }
        #endif
        guard let token = Keychain.get(Self.tokenAccount) else { return }
        begin(with: GitHubClient(token: token))
    }

    /// Settings: a personal access token the user pasted.
    func connect(token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        verifyAndKeep(token: trimmed)
    }

    /// Settings: takes over the login of the GitHub CLI, after a click. wisp keeps its own copy
    /// in the Keychain; `gh` stays logged in.
    func connectWithCLI() {
        guard let token = Self.tokenFromCLI() else {
            status = .failed(String(localized: "GitHub CLI isn't logged in. Run gh auth login, or use a token."))
            return
        }
        verifyAndKeep(token: token)
    }

    /// Whether the GitHub CLI is installed, so Settings can offer it.
    var hasCLI: Bool { Self.cliPath != nil }

    func disconnect() {
        stopPolling()
        Keychain.remove(Self.tokenAccount)
        service = nil
        sync = nil
        status = .disconnected
        snapshot = RadarSnapshot()
        stats = nil
        statsFetched = nil
        repositories = []
        seen = RadarSeen()
        updateCompact()
    }

    private func verifyAndKeep(token: String) {
        status = .connecting
        let client = GitHubClient(token: token)
        Task {
            do {
                _ = try await client.viewerLogin()
                Keychain.set(token, for: Self.tokenAccount)
                begin(with: client)
            } catch {
                status = .failed(Self.message(for: error))
            }
        }
    }

    private func begin(with service: any GitHubService) {
        stopPolling()
        self.service = service
        sync = RadarSync(service: service)
        status = .connecting
        failures = 0
        blockedUntil = nil
        polling = Task { await poll() }
    }

    private static let cliPath: String? = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    private static func tokenFromCLI() -> String? {
        guard let path = cliPath else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["auth", "token"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return token?.isEmpty == false ? token : nil
    }

    // MARK: - Polling

    private func poll() async {
        guard let service, let sync else { return }
        do {
            let login: String
            if let known = self.login {
                login = known
            } else {
                login = try await service.viewerLogin()
                status = .connected(login: login)
                refreshRepositories()
            }
            let result = try await sync.refresh(excluded: excludedRepositories, lastActivity: seen.lastActivity)
            guard !Task.isCancelled else { return }
            apply(result, login: login)
            failures = 0
            blockedUntil = nil
            if tabVisible { refreshStatsIfStale() }
        } catch GitHubError.unauthorized {
            // A rejected key doesn't get better by asking again.
            status = .failed(Self.message(for: GitHubError.unauthorized))
            return
        } catch GitHubError.rateLimited(let until) {
            blockedUntil = until
        } catch is CancellationError {
            return
        } catch {
            // Offline or GitHub is down: keep what is shown and try again later, quietly.
            guard !Task.isCancelled else { return }
            failures += 1
        }
        await scheduleNext()
    }

    private func apply(_ result: RadarSync.Result, login: String) {
        let previous = snapshot
        let diff = Radar.diff(snapshot: result.snapshot, activity: result.activity, login: login, seen: seen)
        snapshot = result.snapshot
        seen = diff.seen
        if previous != result.snapshot || !diff.events.isEmpty { lastChange = .now }
        if tabVisible { seen = Radar.acknowledge(snapshot: snapshot, seen: seen) }
        updateCompact()
        for event in diff.events { onEvent(event) }
    }

    private func scheduleNext() async {
        guard !asleep, service != nil else { return }
        let limit = await service?.rateLimit()
        let input = PollInput(
            anyRunning: snapshot.anyRunning,
            recentlyActive: lastChange.map { Date.now.timeIntervalSince($0) < Self.activeWindow } ?? false,
            consecutiveFailures: failures,
            rateRemaining: limit?.remaining,
            rateReset: limit?.reset,
            blockedUntil: blockedUntil
        )
        schedule(after: PollSchedule.nextDelay(input, now: .now))
    }

    private func schedule(after delay: TimeInterval) {
        wake?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.polling = Task { await self.poll() }
        }
        wake = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func stopPolling() {
        wake?.cancel()
        wake = nil
        polling?.cancel()
        polling = nil
    }

    /// Soon, not now: a few changes in a row (Settings) become one request.
    private func pollSoon() {
        guard service != nil, !asleep, blockedUntil == nil else { return }
        schedule(after: 1)
    }

    private func observeSleep() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let sleep: @Sendable (Notification) -> Void = { _ in
            MainActor.assumeIsolated { GitHubStore.shared.setAsleep(true) }
        }
        let wake: @Sendable (Notification) -> Void = { _ in
            MainActor.assumeIsolated { GitHubStore.shared.setAsleep(false) }
        }
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: sleep))
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: wake))
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main, using: sleep))
        observers.append(distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main, using: wake))
    }

    private func setAsleep(_ on: Bool) {
        guard asleep != on else { return }
        asleep = on
        if on {
            stopPolling()
        } else if service != nil, case .failed = status {
            return
        } else if service != nil {
            // The network needs a moment after waking.
            schedule(after: 3)
        }
    }

    // MARK: - The tab

    /// The GitHub tab appeared or went away. Looking at it clears the dots.
    func setTabVisible(_ on: Bool) {
        tabVisible = on
        guard on else { return }
        acknowledge()
        refreshStatsIfStale()
    }

    func acknowledge() {
        seen = Radar.acknowledge(snapshot: snapshot, seen: seen)
    }

    func refreshRepositories() {
        guard let service else { return }
        Task {
            if let found = try? await service.repositories() { repositories = found }
        }
    }

    private func refreshStatsIfStale() {
        guard let service else { return }
        if let statsFetched, Date.now.timeIntervalSince(statsFetched) < Self.statsMaxAge { return }
        statsFetched = .now
        Task {
            if let fresh = try? await service.contributions(now: .now, calendar: .current) {
                stats = fresh
            } else {
                statsFetched = nil
            }
        }
    }

    private func updateCompact() {
        let notifications = RadarNotifications(failed: notifyFailed, passed: notifyPassed, review: notifyReview,
                                               comments: notifyComments, tick: tickAnimation)
        let new = Radar.compact(snapshot: snapshot, seen: seen, notifications: notifications)
        if new != compact { compact = new }
    }

    private func saveNotifications(_ value: Bool, _ key: String) {
        defaults.set(value, forKey: key)
        updateCompact()
    }

    private static func message(for error: Error) -> String {
        switch error as? GitHubError {
        case .unauthorized: String(localized: "GitHub didn't accept this key.")
        case .rateLimited: String(localized: "GitHub asks wisp to wait a moment.")
        default: String(localized: "Can't reach GitHub.")
        }
    }

    #if DEBUG
    private func startDemo() {
        func pull(_ repo: String, _ number: Int, _ title: String, _ sha: String) -> PullRequest {
            var pull = PullRequest(repository: "demo/\(repo)", number: number, title: title,
                                   url: URL(string: "https://github.com/demo/\(repo)/pull/\(number)")!,
                                   isDraft: false, updatedAt: .now)
            pull.headSHA = sha
            return pull
        }
        let mine = [pull("wisp", 43, "feat: departure engine", "a"), pull("wisp", 42, "feat: PR radar UI", "b"),
                    pull("wisp", 41, "feat: PR radar data layer", "c"), pull("soulroll", 12, "Race-roll balans", "d")]
        let reviews = [pull("wisp", 40, "fix: close the panel on sleep", "e"), pull("soulroll", 11, "Add level select", "f")]
        let checks = [
            "a": CheckSummary(status: .running, completed: 2, total: 5),
            "b": CheckSummary(status: .failed, completed: 5, total: 5, failedJobs: [FailedJob(name: "build", url: nil)]),
            "c": CheckSummary(status: .passed, completed: 5, total: 5),
            "d": CheckSummary(status: .passed, completed: 1, total: 1),
        ]
        var seed = RadarSeen()
        seed.hasBaseline = true
        seed.unseenActivity = ["demo/soulroll#12": 3]
        seen = seed
        let mock = MockGitHubService(mine: mine, reviews: reviews, checks: checks)
        let levels = (0..<16).map { week in (0..<7).map { day in (week * 7 + day * 3) % 5 } }
        Task {
            await mock.setStats(ContributionStats(weeks: levels, streak: 12, commitsThisWeek: 34, mergedThisWeek: 5))
            begin(with: mock)
        }
    }
    #endif
}

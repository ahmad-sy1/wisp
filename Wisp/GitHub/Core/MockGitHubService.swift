import Foundation

/// Answers like GitHub without a network, for the tests and for `-githubDemo` in Debug builds.
/// The repositories and titles are made up.
actor MockGitHubService: GitHubService {
    var mine: [PullRequest]
    var reviews: [PullRequest]
    var checksBySHA: [String: CheckSummary]
    var activityByPull: [String: [PullActivity]] = [:]
    var stats: ContributionStats?
    var failure: GitHubError?
    private(set) var checksCalls = 0
    private(set) var activityCalls = 0

    init(mine: [PullRequest] = [], reviews: [PullRequest] = [], checks: [String: CheckSummary] = [:]) {
        self.mine = mine
        self.reviews = reviews
        checksBySHA = checks
    }

    func set(mine: [PullRequest]? = nil, reviews: [PullRequest]? = nil, checks: [String: CheckSummary]? = nil,
             activity: [String: [PullActivity]]? = nil, failure: GitHubError? = nil) {
        if let mine { self.mine = mine }
        if let reviews { self.reviews = reviews }
        if let checks { checksBySHA = checks }
        if let activity { activityByPull = activity }
        self.failure = failure
    }

    func setStats(_ stats: ContributionStats) {
        self.stats = stats
    }

    func viewerLogin() async throws -> String {
        if let failure { throw failure }
        return "demo"
    }

    func search(_ query: String) async throws -> [PullRequest] {
        if let failure { throw failure }
        return query.contains("review-requested") ? reviews : mine
    }

    func headSHA(repository: String, number: Int) async throws -> String? {
        mine.first { $0.repository == repository && $0.number == number }?.headSHA
    }

    func checks(repository: String, sha: String) async throws -> CheckSummary {
        checksCalls += 1
        return checksBySHA[sha] ?? CheckSummary()
    }

    func activity(repository: String, number: Int, since: Date?) async throws -> [PullActivity] {
        activityCalls += 1
        return (activityByPull["\(repository)#\(number)"] ?? []).filter { since == nil || $0.date > since! }
    }

    func contributions(now: Date, calendar: Calendar) async throws -> ContributionStats {
        if let failure { throw failure }
        return stats ?? ContributionStats(weeks: [], streak: 0, commitsThisWeek: 0, mergedThisWeek: 0)
    }

    func repositories() async throws -> [GitHubRepository] {
        Array(Set(mine.map(\.repository) + reviews.map(\.repository))).sorted().map { GitHubRepository(fullName: $0) }
    }

    func rateLimit() async -> (remaining: Int?, reset: Date?) { (nil, nil) }
}

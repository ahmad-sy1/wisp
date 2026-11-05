import Foundation

enum GitHubError: Error, Equatable, Sendable {
    case notConnected
    case unauthorized
    case rateLimited(until: Date)
    case http(Int)
    case decoding
}

/// Everything the radar asks of GitHub; `MockGitHubService` answers without a network.
protocol GitHubService: Sendable {
    func viewerLogin() async throws -> String
    func search(_ query: String) async throws -> [PullRequest]
    func headSHA(repository: String, number: Int) async throws -> String?
    func checks(repository: String, sha: String) async throws -> CheckSummary
    func activity(repository: String, number: Int, since: Date?) async throws -> [PullActivity]
    func contributions(now: Date, calendar: Calendar) async throws -> ContributionStats
    func repositories() async throws -> [GitHubRepository]
    func rateLimit() async -> (remaining: Int?, reset: Date?)
}

/// GitHub's REST and GraphQL API with conditional requests: every GET remembers its ETag, and
/// a 304 (which doesn't count against the rate limit) reuses the previous body.
actor GitHubClient: GitHubService {
    private let transport: any HTTPTransport
    private let token: String
    private let base: URL
    private var cache: [URL: (etag: String, body: Data)] = [:]
    private var remaining: Int?
    private var reset: Date?

    init(token: String, transport: any HTTPTransport = URLSessionTransport(),
         base: URL = URL(string: "https://api.github.com")!) {
        self.token = token
        self.transport = transport
        self.base = base
    }

    func rateLimit() -> (remaining: Int?, reset: Date?) { (remaining, reset) }

    // MARK: - Requests

    private func headers() -> [String: String] {
        ["Authorization": "Bearer \(token)",
         "Accept": "application/vnd.github+json",
         "X-GitHub-Api-Version": "2022-11-28",
         "User-Agent": "wisp"]
    }

    private func url(_ path: String, _ query: [String: String] = [:]) throws -> URL {
        guard var parts = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        else { throw GitHubError.decoding }
        if !query.isEmpty {
            parts.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = parts.url else { throw GitHubError.decoding }
        return url
    }

    private func get<T: Decodable & Sendable>(_ type: T.Type, _ path: String, _ query: [String: String] = [:]) async throws -> T {
        let url = try url(path, query)
        var request = HTTPRequest(url: url, headers: headers())
        if let cached = cache[url] { request.headers["If-None-Match"] = cached.etag }
        let response = try await transport.send(request)
        try note(response)
        if response.status == 304, let cached = cache[url] {
            return try decode(type, cached.body)
        }
        try check(response)
        if let etag = response.headers["etag"] { cache[url] = (etag, response.body) }
        return try decode(type, response.body)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try Self.decoder.decode(type, from: data) } catch { throw GitHubError.decoding }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func note(_ response: HTTPResponse) throws {
        if let value = response.headers["x-ratelimit-remaining"].flatMap(Int.init) { remaining = value }
        if let value = response.headers["x-ratelimit-reset"].flatMap(TimeInterval.init) {
            reset = Date(timeIntervalSince1970: value)
        }
    }

    private func check(_ response: HTTPResponse) throws {
        switch response.status {
        case 200..<300:
            return
        case 401:
            throw GitHubError.unauthorized
        case 403, 429:
            if let seconds = response.headers["retry-after"].flatMap(TimeInterval.init) {
                throw GitHubError.rateLimited(until: Date(timeIntervalSinceNow: seconds))
            }
            if remaining == 0, let reset { throw GitHubError.rateLimited(until: reset) }
            throw GitHubError.http(response.status)
        default:
            throw GitHubError.http(response.status)
        }
    }

    // MARK: - Radar

    func viewerLogin() async throws -> String {
        struct User: Decodable { let login: String }
        return try await get(User.self, "user").login
    }

    func search(_ query: String) async throws -> [PullRequest] {
        struct Answer: Decodable, Sendable {
            struct Item: Decodable, Sendable {
                struct User: Decodable, Sendable { let login: String }
                let number: Int
                let title: String
                let html_url: URL
                let repository_url: URL
                let updated_at: Date
                let draft: Bool?
                let user: User?
            }
            let items: [Item]
        }
        let answer = try await get(Answer.self, "search/issues", ["q": query, "per_page": "30", "sort": "updated"])
        return answer.items.map { item in
            let parts = item.repository_url.pathComponents.suffix(2)
            return PullRequest(repository: parts.joined(separator: "/"), number: item.number, title: item.title,
                               url: item.html_url, isDraft: item.draft ?? false, updatedAt: item.updated_at,
                               author: item.user?.login)
        }
    }

    func headSHA(repository: String, number: Int) async throws -> String? {
        struct Pull: Decodable, Sendable {
            struct Head: Decodable, Sendable { let sha: String }
            let head: Head
        }
        return try await get(Pull.self, "repos/\(repository)/pulls/\(number)").head.sha
    }

    func checks(repository: String, sha: String) async throws -> CheckSummary {
        struct Runs: Decodable, Sendable {
            struct Run: Decodable, Sendable {
                let name: String
                let status: String
                let conclusion: String?
                let html_url: URL?
            }
            let check_runs: [Run]
        }
        struct Statuses: Decodable, Sendable {
            struct Status: Decodable, Sendable {
                let context: String
                let state: String
                let target_url: String?
            }
            let statuses: [Status]
        }
        let runs = try await get(Runs.self, "repos/\(repository)/commits/\(sha)/check-runs", ["per_page": "100"])
        let statuses = try await get(Statuses.self, "repos/\(repository)/commits/\(sha)/status", ["per_page": "100"])
        return CheckAggregator.summarize(
            runs: runs.check_runs.map { CheckRun(name: $0.name, status: $0.status, conclusion: $0.conclusion, url: $0.html_url) },
            statuses: statuses.statuses.map { CommitStatus(context: $0.context, state: $0.state, url: $0.target_url.flatMap(URL.init(string:))) }
        )
    }

    func activity(repository: String, number: Int, since: Date?) async throws -> [PullActivity] {
        struct User: Decodable, Sendable { let login: String }
        struct Comment: Decodable, Sendable {
            let user: User?
            let created_at: Date
            let html_url: URL?
        }
        struct Review: Decodable, Sendable {
            let user: User?
            let state: String
            let submitted_at: Date?
            let html_url: URL?
        }
        var query = ["per_page": "100"]
        if let since { query["since"] = ISO8601DateFormatter().string(from: since) }
        let comments = try await get([Comment].self, "repos/\(repository)/issues/\(number)/comments", query)
        let inline = try await get([Comment].self, "repos/\(repository)/pulls/\(number)/comments", query)
        let reviews = try await get([Review].self, "repos/\(repository)/pulls/\(number)/reviews", ["per_page": "100"])
        var result: [PullActivity] = []
        result += comments.compactMap { comment in
            comment.user.map { PullActivity(kind: .comment, author: $0.login, date: comment.created_at, url: comment.html_url) }
        }
        result += inline.compactMap { comment in
            comment.user.map { PullActivity(kind: .reviewComment, author: $0.login, date: comment.created_at, url: comment.html_url) }
        }
        result += reviews.compactMap { review in
            guard let user = review.user, let date = review.submitted_at, review.state != "PENDING",
                  since == nil || date > since! else { return nil }
            return PullActivity(kind: .review, author: user.login, date: date, url: review.html_url)
        }
        return result
    }

    func repositories() async throws -> [GitHubRepository] {
        struct Repo: Decodable, Sendable { let full_name: String; let archived: Bool? }
        let repos = try await get([Repo].self, "user/repos", ["per_page": "100", "sort": "pushed"])
        return repos.filter { $0.archived != true }.map { GitHubRepository(fullName: $0.full_name) }
    }

    // MARK: - Contributions

    /// One GraphQL request: a year of days (for the streak), of which the tab draws 16 weeks,
    /// this week's commits and the merged pull requests. A POST has no ETag, so the store asks
    /// rarely and only while the tab is open.
    func contributions(now: Date, calendar: Calendar) async throws -> ContributionStats {
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let yearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        let iso = ISO8601DateFormatter()
        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        let body: [String: Any] = [
            "query": """
            query($from: DateTime!, $to: DateTime!, $week: DateTime!, $merged: String!) {
              viewer {
                year: contributionsCollection(from: $from, to: $to) {
                  contributionCalendar { weeks { contributionDays { contributionCount contributionLevel } } }
                }
                week: contributionsCollection(from: $week, to: $to) { totalCommitContributions }
              }
              search(query: $merged, type: ISSUE, first: 1) { issueCount }
            }
            """,
            "variables": [
                "from": iso.string(from: yearAgo),
                "to": iso.string(from: now),
                "week": iso.string(from: weekAgo),
                "merged": "is:pr author:@me is:merged merged:>=\(day.string(from: weekAgo))",
            ],
        ]
        var request = HTTPRequest(url: try url("graphql"), method: "POST", headers: headers())
        request.headers["Content-Type"] = "application/json"
        request.body = try JSONSerialization.data(withJSONObject: body)
        let response = try await transport.send(request)
        try note(response)
        try check(response)
        return try Self.parseContributions(response.body)
    }

    static func parseContributions(_ data: Data, weeksShown: Int = 16) throws -> ContributionStats {
        struct Answer: Decodable {
            struct DataPart: Decodable {
                struct Viewer: Decodable {
                    struct Year: Decodable {
                        struct Calendar: Decodable {
                            struct Week: Decodable {
                                struct Day: Decodable { let contributionCount: Int; let contributionLevel: String }
                                let contributionDays: [Day]
                            }
                            let weeks: [Week]
                        }
                        let contributionCalendar: Calendar
                    }
                    struct Week: Decodable { let totalCommitContributions: Int }
                    let year: Year
                    let week: Week
                }
                struct Search: Decodable { let issueCount: Int }
                let viewer: Viewer
                let search: Search
            }
            let data: DataPart?
        }
        guard let part = try? JSONDecoder().decode(Answer.self, from: data).data else { throw GitHubError.decoding }
        let weeks = part.viewer.year.contributionCalendar.weeks
        let days = weeks.flatMap(\.contributionDays).map(\.contributionCount)
        let levels = weeks.suffix(weeksShown).map { week in
            week.contributionDays.map { day -> Int in
                switch day.contributionLevel {
                case "FIRST_QUARTILE": 1
                case "SECOND_QUARTILE": 2
                case "THIRD_QUARTILE": 3
                case "FOURTH_QUARTILE": 4
                default: 0
                }
            }
        }
        return ContributionStats(weeks: Array(levels), streak: Radar.streak(days: days),
                                 commitsThisWeek: part.viewer.week.totalCommitContributions,
                                 mergedThisWeek: part.search.issueCount)
    }
}

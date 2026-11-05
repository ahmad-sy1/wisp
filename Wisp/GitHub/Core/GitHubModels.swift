import Foundation

/// The state of the checks on a pull request's latest commit.
enum CheckStatus: String, Codable, Sendable {
    case none, running, passed, failed
}

/// One job that failed, with the page that explains why.
struct FailedJob: Equatable, Codable, Sendable {
    let name: String
    let url: URL?
}

/// All checks of one commit, added up.
struct CheckSummary: Equatable, Codable, Sendable {
    var status: CheckStatus = .none
    var completed = 0
    var total = 0
    var failedJobs: [FailedJob] = []
    /// The run page: the failed job's, or else the first running one.
    var url: URL?
}

/// An open pull request as the radar shows it.
struct PullRequest: Identifiable, Equatable, Codable, Sendable {
    /// "owner/name".
    let repository: String
    let number: Int
    var title: String
    let url: URL
    var isDraft: Bool
    var updatedAt: Date
    var author: String?
    var headSHA: String?
    var checks = CheckSummary()

    var id: String { "\(repository)#\(number)" }
    /// "wisp" from "ahmad-sy1/wisp".
    var repositoryName: String { repository.split(separator: "/").last.map(String.init) ?? repository }
}

/// A comment or review somebody left on a pull request.
struct PullActivity: Equatable, Sendable {
    enum Kind: String, Sendable { case comment, reviewComment, review }

    let kind: Kind
    let author: String
    let date: Date
    let url: URL?
}

/// Something new that deserves one short animation, once.
enum RadarEvent: Equatable, Sendable {
    case checksFailed(PullRequest, FailedJob?)
    case checksPassed(PullRequest)
    case reviewRequested(PullRequest)
    case newActivity(PullRequest, author: String, count: Int)
}

/// The contribution graph of the GitHub tab.
struct ContributionStats: Equatable, Codable, Sendable {
    /// One array per week, oldest first; each day's level is 0–4 (GitHub's own quartiles).
    var weeks: [[Int]]
    var streak: Int
    var commitsThisWeek: Int
    var mergedThisWeek: Int
}

struct GitHubRepository: Identifiable, Equatable, Codable, Sendable {
    /// "owner/name".
    let fullName: String
    var id: String { fullName }
}

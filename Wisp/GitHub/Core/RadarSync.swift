import Foundation

/// One round of asking GitHub: both searches, then for each of your pull requests only what
/// may have changed. The head commit and comments are fetched when `updatedAt` moved (a push or
/// a comment moves it); checks don't move it, so those are asked each round, but with an ETag.
actor RadarSync {
    struct Result: Sendable {
        let snapshot: RadarSnapshot
        /// New comments and reviews per pull request.
        let activity: [String: [PullActivity]]
    }

    private let service: any GitHubService
    private var known: [String: PullRequest] = [:]

    init(service: any GitHubService) {
        self.service = service
    }

    /// `lastActivity`: what is already reported, so only newer comments are fetched.
    func refresh(excluded: Set<String>, lastActivity: [String: Date]) async throws -> Result {
        async let mineSearch = service.search("is:pr is:open author:@me archived:false")
        async let reviewSearch = service.search("is:pr is:open review-requested:@me archived:false")
        let mine = try await mineSearch.filter { !excluded.contains($0.repository) }
        let reviews = try await reviewSearch.filter { !excluded.contains($0.repository) }

        var activity: [String: [PullActivity]] = [:]
        var updated: [PullRequest] = []
        for var pull in mine {
            let previous = known[pull.id]
            let moved = previous?.updatedAt != pull.updatedAt
            pull.headSHA = previous?.headSHA
            pull.checks = previous?.checks ?? CheckSummary()
            if moved || pull.headSHA == nil {
                pull.headSHA = try await service.headSHA(repository: pull.repository, number: pull.number)
                let items = try await service.activity(repository: pull.repository, number: pull.number,
                                                       since: lastActivity[pull.id])
                if !items.isEmpty { activity[pull.id] = items }
            }
            if let sha = pull.headSHA {
                pull.checks = try await service.checks(repository: pull.repository, sha: sha)
            }
            updated.append(pull)
        }
        known = Dictionary(uniqueKeysWithValues: updated.map { ($0.id, $0) })
        return Result(snapshot: RadarSnapshot(mine: updated, reviews: reviews), activity: activity)
    }
}

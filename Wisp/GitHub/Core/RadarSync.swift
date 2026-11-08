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
    private static let batchSize = 6

    init(service: any GitHubService) {
        self.service = service
    }

    /// `lastActivity`: what is already reported, so only newer comments are fetched.
    /// `found`: called once on the first round, right after the searches, so the list shows
    /// before all the checks are in.
    func refresh(
        excluded: Set<String>, lastActivity: [String: Date],
        found: (@Sendable (RadarSnapshot) async -> Void)? = nil
    ) async throws -> Result {
        async let mineSearch = service.search("is:pr is:open author:@me archived:false")
        async let reviewSearch = service.search("is:pr is:open review-requested:@me archived:false")
        let mine = try await mineSearch.filter { !excluded.contains($0.repository) }
        let reviews = try await reviewSearch.filter { !excluded.contains($0.repository) }

        if known.isEmpty, let found {
            await found(RadarSnapshot(mine: mine, reviews: reviews))
        }

        var activity: [String: [PullActivity]] = [:]
        var updated: [PullRequest] = []
        // A few at a time: quick enough for a first look, gentle on GitHub's limits.
        var start = 0
        while start < mine.count {
            let batch = mine[start..<min(start + Self.batchSize, mine.count)]
            start += batch.count
            let results = try await withThrowingTaskGroup(of: (Int, PullRequest, [PullActivity]).self) { group in
                for (index, pull) in batch.enumerated() {
                    let previous = known[pull.id]
                    let since = lastActivity[pull.id]
                    group.addTask { [service] in
                        let (fresh, items) = try await Self.update(pull, previous: previous, since: since, service: service)
                        return (index, fresh, items)
                    }
                }
                var all: [(Int, PullRequest, [PullActivity])] = []
                for try await result in group { all.append(result) }
                return all.sorted { $0.0 < $1.0 }
            }
            for (_, pull, items) in results {
                updated.append(pull)
                if !items.isEmpty { activity[pull.id] = items }
            }
        }
        known = Dictionary(uniqueKeysWithValues: updated.map { ($0.id, $0) })
        return Result(snapshot: RadarSnapshot(mine: updated, reviews: reviews), activity: activity)
    }

    private static func update(
        _ found: PullRequest, previous: PullRequest?, since: Date?,
        service: any GitHubService
    ) async throws -> (PullRequest, [PullActivity]) {
        var pull = found
        var items: [PullActivity] = []
        pull.headSHA = previous?.headSHA
        pull.checks = previous?.checks ?? CheckSummary()
        if previous?.updatedAt != pull.updatedAt || pull.headSHA == nil {
            pull.headSHA = try await service.headSHA(repository: pull.repository, number: pull.number)
            // Seen for the first time with nothing reported yet: old comments aren't news, so
            // don't ask for them. From here on, what is newer than this moment counts.
            if let after = since ?? previous?.updatedAt {
                items = try await service.activity(repository: pull.repository, number: pull.number, since: after)
            }
        }
        if let sha = pull.headSHA {
            pull.checks = try await service.checks(repository: pull.repository, sha: sha)
        }
        return (pull, items)
    }
}

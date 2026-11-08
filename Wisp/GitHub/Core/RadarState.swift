import Foundation

/// What the notch has already told you, kept between launches so an animation goes off
/// once per event and not again after a restart.
struct RadarSeen: Codable, Equatable, Sendable {
    struct Check: Codable, Equatable, Sendable {
        var sha: String?
        var status: CheckStatus
    }

    var checks: [String: Check] = [:]
    var reviewRequests: Set<String> = []
    /// The newest comment or review already reported, per pull request.
    var lastActivity: [String: Date] = [:]
    /// Comments you haven't looked at yet, per pull request; cleared by opening the tab.
    var unseenActivity: [String: Int] = [:]
    /// "owner/repo#1@sha" of failures you have looked at: their dot may go.
    var acknowledgedFailures: Set<String> = []
    /// Review requests you have looked at: the blue dot may go.
    var acknowledgedReviews: Set<String> = []
    /// False until the first answer: what is there already is not news.
    var hasBaseline = false
}

/// All open pull requests the radar knows about.
struct RadarSnapshot: Equatable, Codable, Sendable {
    var mine: [PullRequest] = []
    var reviews: [PullRequest] = []

    var anyRunning: Bool { mine.contains { $0.checks.status == .running } }
}

/// One small indicator on the closed notch (design page 1). Nothing wrong shows nothing.
enum RadarCompact: Equatable, Sendable {
    case none
    case running(completed: Int, total: Int)
    case failed(PullRequest)
    case reviewRequested(PullRequest, count: Int)
    case newActivity(PullRequest, count: Int)
}

/// What the user wants to hear about (Settings → GitHub).
struct RadarNotifications: Equatable, Sendable {
    var failed = true
    var passed = true
    var review = true
    var comments = true
    var tick = true
}

enum Radar {
    static func failureKey(_ pull: PullRequest) -> String { "\(pull.id)@\(pull.headSHA ?? "")" }

    /// Compares a fresh snapshot with what was seen: the events to report, and the updated seen state.
    /// `activity` holds, per pull request, what the store fetched for those whose `updatedAt` moved.
    static func diff(
        snapshot: RadarSnapshot, activity: [String: [PullActivity]], login: String,
        seen old: RadarSeen
    ) -> (events: [RadarEvent], seen: RadarSeen) {
        var seen = old
        var events: [RadarEvent] = []
        let silent = !old.hasBaseline

        for pull in snapshot.mine {
            let previous = old.checks[pull.id]
            let status = pull.checks.status
            let changed = previous?.status != status || previous?.sha != pull.headSHA
            if changed && !silent {
                // A pull request seen for the first time reports only a failure: it may be years
                // old and green, which is not news.
                switch status {
                case .failed:
                    events.append(.checksFailed(pull, pull.checks.failedJobs.first))
                case .passed where previous != nil:
                    events.append(.checksPassed(pull))
                default:
                    break
                }
            }
            seen.checks[pull.id] = RadarSeen.Check(sha: pull.headSHA, status: status)

            let items = (activity[pull.id] ?? [])
                .filter { $0.author.caseInsensitiveCompare(login) != .orderedSame && !$0.author.hasSuffix("[bot]") }
                .sorted { $0.date < $1.date }
            if let newest = items.last {
                let last = old.lastActivity[pull.id]
                let fresh = items.filter { last == nil || $0.date > last! }
                if !fresh.isEmpty {
                    seen.lastActivity[pull.id] = newest.date
                    if !silent {
                        seen.unseenActivity[pull.id, default: 0] += fresh.count
                        events.append(.newActivity(pull, author: fresh.last!.author, count: fresh.count))
                    }
                }
            }
        }

        let requested = Set(snapshot.reviews.map(\.id))
        if !silent {
            for pull in snapshot.reviews where !old.reviewRequests.contains(pull.id) {
                events.append(.reviewRequested(pull))
            }
        }
        seen.reviewRequests = requested

        // Forget what is gone, so the saved state stays small and a re-request counts as new.
        let open = Set(snapshot.mine.map(\.id))
        seen.checks = seen.checks.filter { open.contains($0.key) }
        seen.lastActivity = seen.lastActivity.filter { open.contains($0.key) }
        seen.unseenActivity = seen.unseenActivity.filter { open.contains($0.key) }
        let currentFailures = Set(snapshot.mine.map(failureKey))
        seen.acknowledgedFailures.formIntersection(currentFailures)
        seen.acknowledgedReviews.formIntersection(requested)
        seen.hasBaseline = true
        return (events, seen)
    }

    /// The user looked at the tab: dots may go.
    static func acknowledge(snapshot: RadarSnapshot, seen old: RadarSeen) -> RadarSeen {
        var seen = old
        for pull in snapshot.mine where pull.checks.status == .failed {
            seen.acknowledgedFailures.insert(failureKey(pull))
        }
        seen.acknowledgedReviews.formUnion(snapshot.reviews.map(\.id))
        seen.unseenActivity = [:]
        return seen
    }

    /// What the closed notch shows, most urgent first: failed, review, comments, running.
    static func compact(snapshot: RadarSnapshot, seen: RadarSeen, notifications: RadarNotifications) -> RadarCompact {
        if notifications.failed,
            let pull = snapshot.mine.first(where: {
                $0.checks.status == .failed && !seen.acknowledgedFailures.contains(failureKey($0))
            })
        {
            return .failed(pull)
        }
        if notifications.review {
            let waiting = snapshot.reviews.filter { !seen.acknowledgedReviews.contains($0.id) }
            if let first = waiting.first { return .reviewRequested(first, count: waiting.count) }
        }
        if notifications.comments,
            let pull = snapshot.mine.first(where: { (seen.unseenActivity[$0.id] ?? 0) > 0 })
        {
            return .newActivity(pull, count: seen.unseenActivity[pull.id] ?? 0)
        }
        let running = snapshot.mine.filter { $0.checks.status == .running }
        if !running.isEmpty {
            return .running(
                completed: running.reduce(0) { $0 + $1.checks.completed },
                total: running.reduce(0) { $0 + $1.checks.total })
        }
        return .none
    }

    /// Consecutive days with a contribution up to today. A today without one doesn't break the
    /// streak yet: the day isn't over.
    static func streak(days: [Int]) -> Int {
        var counts = days[...]
        if counts.last == 0 { counts = counts.dropLast() }
        var streak = 0
        for count in counts.reversed() {
            guard count > 0 else { break }
            streak += 1
        }
        return streak
    }
}

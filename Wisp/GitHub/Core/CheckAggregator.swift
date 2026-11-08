import Foundation

/// A check run from `GET /repos/{repo}/commits/{sha}/check-runs`.
struct CheckRun: Equatable, Sendable {
    let name: String
    /// queued, in_progress, completed, waiting, requested, pending.
    let status: String
    /// success, failure, neutral, cancelled, skipped, timed_out, action_required, stale, startup_failure.
    let conclusion: String?
    let url: URL?
}

/// A commit status from `GET /repos/{repo}/commits/{sha}/status` (older CI services).
struct CommitStatus: Equatable, Sendable {
    let context: String
    /// error, failure, pending, success.
    let state: String
    let url: URL?
}

enum CheckAggregator {
    private static let failedConclusions: Set<String> = ["failure", "timed_out", "startup_failure"]

    /// Adds up one commit's checks. A failure wins straight away, even while other jobs run:
    /// that is what you want to know. A cancelled or skipped job counts as finished, not failed.
    static func summarize(runs: [CheckRun], statuses: [CommitStatus]) -> CheckSummary {
        var failed: [FailedJob] = []
        var running = false
        var completed = 0
        var firstRunning: URL?

        for run in runs {
            if run.status == "completed" {
                completed += 1
                if let conclusion = run.conclusion, failedConclusions.contains(conclusion) {
                    failed.append(FailedJob(name: run.name, url: run.url))
                }
            } else {
                running = true
                if firstRunning == nil { firstRunning = run.url }
            }
        }
        for status in statuses {
            switch status.state {
            case "pending":
                running = true
                if firstRunning == nil { firstRunning = status.url }
            case "failure", "error":
                completed += 1
                failed.append(FailedJob(name: status.context, url: status.url))
            default:
                completed += 1
            }
        }

        let total = runs.count + statuses.count
        let status: CheckStatus = if total == 0 { .none }
            else if !failed.isEmpty { .failed }
            else if running { .running }
            else { .passed }
        return CheckSummary(status: status, completed: completed, total: total, failedJobs: failed,
                            url: failed.first?.url ?? firstRunning)
    }
}

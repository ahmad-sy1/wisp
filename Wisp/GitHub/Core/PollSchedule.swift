import Foundation

/// What decides when wisp asks GitHub again.
struct PollInput: Equatable, Sendable {
    var anyRunning = false
    /// A check finished or something else changed a moment ago; more may follow.
    var recentlyActive = false
    var consecutiveFailures = 0
    /// GitHub's own rate-limit numbers from the last answer.
    var rateRemaining: Int?
    var rateReset: Date?
    /// Set when GitHub told us to back off (Retry-After or an exhausted limit).
    var blockedUntil: Date?
}

/// Adaptive polling: quick while a run is going, calm when nothing happens, and always
/// behind whatever GitHub asks for.
enum PollSchedule {
    static let running: TimeInterval = 25
    static let active: TimeInterval = 60
    static let quiet: TimeInterval = 180
    static let maxBackoff: TimeInterval = 15 * 60
    /// Below this many requests left wisp waits for the limit to reset.
    static let lowRateLimit = 100

    static func nextDelay(_ input: PollInput, now: Date) -> TimeInterval {
        var delay: TimeInterval
        if input.consecutiveFailures > 0 {
            let exponent = min(input.consecutiveFailures - 1, 8)
            delay = min(maxBackoff, 60 * pow(2, Double(exponent)))
        } else if input.anyRunning {
            delay = running
        } else if input.recentlyActive {
            delay = active
        } else {
            delay = quiet
        }
        if let blockedUntil = input.blockedUntil {
            delay = max(delay, blockedUntil.timeIntervalSince(now))
        }
        if let remaining = input.rateRemaining, remaining < lowRateLimit, let reset = input.rateReset {
            delay = max(delay, reset.timeIntervalSince(now))
        }
        return delay
    }
}

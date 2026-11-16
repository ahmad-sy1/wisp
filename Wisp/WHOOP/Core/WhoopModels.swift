import Foundation

/// What the WHOOP tab shows: the latest scored recovery, sleep and strain. Each part is
/// `nil` until WHOOP has scored it.
struct WhoopToday: Equatable, Codable, Sendable {
    struct Recovery: Equatable, Codable, Sendable {
        let score: Int
        let hrv: Int
        let restingHeartRate: Int
        /// Oldest first, today's last: up to seven scores for the small bars.
        let recent: [Int]
    }

    struct Sleep: Equatable, Codable, Sendable {
        let deep: TimeInterval
        let light: TimeInterval
        let rem: TimeInterval
        let awake: TimeInterval
        let performance: Int?

        var asleep: TimeInterval { deep + light + rem }
    }

    struct Strain: Equatable, Codable, Sendable {
        let score: Double
        let kilocalories: Int?

        static let maximum = 21.0
    }

    var recovery: Recovery?
    var sleep: Sleep?
    var strain: Strain?

    var isEmpty: Bool { recovery == nil && sleep == nil && strain == nil }
}

/// WHOOP's colour bands for recovery.
enum RecoveryZone: Equatable, Sendable {
    case red, yellow, green

    init(_ score: Int) {
        switch score {
        case 67...: self = .green
        case 34...: self = .yellow
        default: self = .red
        }
    }
}

/// Reads the v2 collections. Only records WHOOP has scored count.
enum WhoopParser {
    private struct Page<Record: Decodable>: Decodable {
        let records: [Record]
    }

    private struct RecoveryRecord: Decodable {
        struct Score: Decodable {
            let recovery_score: Double
            let resting_heart_rate: Double
            let hrv_rmssd_milli: Double
        }
        let score_state: String
        let score: Score?
    }

    private struct SleepRecord: Decodable {
        struct Score: Decodable {
            struct Stages: Decodable {
                let total_awake_time_milli: Double
                let total_light_sleep_time_milli: Double
                let total_slow_wave_sleep_time_milli: Double
                let total_rem_sleep_time_milli: Double
            }
            let stage_summary: Stages
            let sleep_performance_percentage: Double?
        }
        let nap: Bool
        let score_state: String
        let score: Score?
    }

    private struct CycleRecord: Decodable {
        struct Score: Decodable {
            let strain: Double
            let kilojoule: Double?
        }
        let score_state: String
        let score: Score?
    }

    /// Records come newest first.
    static func recovery(_ data: Data) throws -> WhoopToday.Recovery? {
        let scored = try JSONDecoder().decode(Page<RecoveryRecord>.self, from: data).records
            .compactMap { $0.score_state == "SCORED" ? $0.score : nil }
        guard let latest = scored.first else { return nil }
        return WhoopToday.Recovery(
            score: Int(latest.recovery_score.rounded()),
            hrv: Int(latest.hrv_rmssd_milli.rounded()),
            restingHeartRate: Int(latest.resting_heart_rate.rounded()),
            recent: scored.prefix(7).reversed().map { Int($0.recovery_score.rounded()) })
    }

    /// The last night; naps don't count.
    static func sleep(_ data: Data) throws -> WhoopToday.Sleep? {
        let night = try JSONDecoder().decode(Page<SleepRecord>.self, from: data).records
            .first { !$0.nap && $0.score_state == "SCORED" && $0.score != nil }
        guard let score = night?.score else { return nil }
        let stages = score.stage_summary
        return WhoopToday.Sleep(
            deep: stages.total_slow_wave_sleep_time_milli / 1000,
            light: stages.total_light_sleep_time_milli / 1000,
            rem: stages.total_rem_sleep_time_milli / 1000,
            awake: stages.total_awake_time_milli / 1000,
            performance: score.sleep_performance_percentage.map { Int($0.rounded()) })
    }

    /// The current cycle, which WHOOP scores as the day goes on.
    static func strain(_ data: Data) throws -> WhoopToday.Strain? {
        let cycle = try JSONDecoder().decode(Page<CycleRecord>.self, from: data).records
            .first { $0.score_state == "SCORED" && $0.score != nil }
        guard let score = cycle?.score else { return nil }
        return WhoopToday.Strain(
            score: (score.strain * 10).rounded() / 10,
            kilocalories: score.kilojoule.map { Int(($0 / 4.184).rounded()) })
    }

    static func firstName(_ data: Data) throws -> String {
        struct Profile: Decodable { let first_name: String }
        return try JSONDecoder().decode(Profile.self, from: data).first_name
    }
}

/// "7h 12m".
enum WhoopFormat {
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

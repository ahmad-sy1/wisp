import Foundation
import SwiftUI

extension TravelMode {
    var symbol: String {
        switch self {
        case .transit: "tram"
        case .car: "car"
        case .bike: "bicycle"
        }
    }

    var title: String {
        switch self {
        case .transit: String(localized: "Public transport")
        case .car: String(localized: "Car")
        case .bike: String(localized: "Bike")
        }
    }

    /// "22 min cycling".
    func duration(_ minutes: Int) -> String {
        switch self {
        case .bike: String(localized: "\(minutes) min cycling")
        case .car: String(localized: "\(minutes) min driving")
        case .transit: String(localized: "\(minutes) min by transit")
        }
    }
}

extension DepartureOutput.Urgency {
    /// White normally, orange when tight, red when it goes wrong.
    var color: Color {
        switch self {
        case .normal: Theme.textPrimary
        case .tight: Theme.warning
        case .serious: Theme.badge
        }
    }
}

extension TravelLeg {
    var isScheduled: Bool { kind != .walk && kind != .drive && kind != .bike }

    /// "Bus 300", "Train".
    var name: String {
        switch kind {
        case .rail: String(localized: "Train")
        case .bus: line.map { String(localized: "Bus \($0)") } ?? String(localized: "Bus")
        case .tram: line.map { String(localized: "Tram \($0)") } ?? String(localized: "Tram")
        case .metro: line.map { String(localized: "Metro \($0)") } ?? String(localized: "Metro")
        case .ferry: String(localized: "Ferry")
        case .walk: String(localized: "Walk")
        case .drive: String(localized: "Drive")
        case .bike: String(localized: "Bike")
        }
    }
}

extension TravelOption {
    /// "Train → Bus 300".
    var summary: String {
        legs.filter(\.isScheduled).map(\.name).joined(separator: " → ")
    }

    /// The first train or bus.
    var firstRide: TravelLeg? { legs.first(where: \.isScheduled) }

    /// "op tijd", "+4 min", "uitval".
    var statusText: String {
        if isCancelled { return String(localized: "cancelled") }
        if delayMinutes > 0 { return "+\(delayMinutes) min" }
        return String(localized: "on time")
    }
}

extension StatusWings {
    /// A trip on the closed notch (design page 1): the countdown left, what to know right.
    init(_ output: DepartureOutput) {
        let minutes = output.minutesUntilLeave
        let left = minutes == 0 ? String(localized: "now") : String(localized: "\(minutes) min")
        var right = ""
        var rightColor = Theme.textSecondary
        var rightSymbol: String?
        let chosen = output.chosen

        switch output.plan.mode {
        case .transit:
            if let chosen, chosen.isCancelled || chosen.delayMinutes > 0 {
                right = chosen.statusText
                rightColor = output.delayUrgency.color
            } else if let ride = chosen?.firstRide, let departure = ride.departure {
                right = ride.platform.map { String(localized: "\(departure.clockTime) platform \($0)") } ?? departure.clockTime
            } else if let chosen {
                right = chosen.arrival.clockTime
            }
        case .car:
            if let chosen, chosen.trafficMinutes >= DepartureEngine.tightDelay {
                let road = chosen.routeName.map { " \($0)" } ?? ""
                right = String(localized: "+\(chosen.trafficMinutes) traffic\(road)")
                rightColor = output.delayUrgency.color
            } else if let chosen {
                right = chosen.arrival.clockTime
            }
        case .bike:
            if let starts = output.rain?.startsInMinutes {
                right = String(localized: "rain \(starts) min")
                rightColor = Theme.rain
                rightSymbol = "cloud.rain"
            } else if let chosen {
                right = chosen.arrival.clockTime
            }
        }
        self.init(
            icon: .symbol(output.plan.mode.symbol, output.timeUrgency == .normal ? Theme.textPrimary : output.timeUrgency.color),
            left: left, leftColor: output.timeUrgency.color,
            right: right, rightColor: rightColor, rightSymbol: rightSymbol, urgent: true, tab: .departure)
    }
}

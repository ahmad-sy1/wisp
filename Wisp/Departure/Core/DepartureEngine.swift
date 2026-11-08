import Foundation

/// A trip that matters now.
struct TripPlan: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case home, event }

    var kind: Kind
    var eventID: String
    var title: String
    var origin: TravelPlace
    var destination: TravelPlace
    var mode: TravelMode
    /// You have to be there by then (the event starts); nil on the way home.
    var arriveBy: Date?
    /// Not before: the moment the last event ends, on the way home.
    var earliestLeave: Date?
}

/// What the notch and tab show. One simple answer: what to do, in which colour.
struct DepartureOutput: Equatable, Sendable {
    enum Urgency: Int, Comparable, Sendable {
        case normal, tight, serious
        static func < (a: Urgency, b: Urgency) -> Bool { a.rawValue < b.rawValue }
    }

    var plan: TripPlan
    var chosen: TravelOption?
    /// Other ways, the chosen one first, as the tab lists them.
    var alternatives: [TravelOption] = []
    var minutesUntilLeave = 0
    /// Orange when you almost have to go. Colours the countdown.
    var timeUrgency: Urgency = .normal
    /// Red for a delay, a cancelled train or a jam. Colours the extra.
    var delayUrgency: Urgency = .normal
    /// You won't make it on time, whichever way.
    var isLate = false
    var later: LaterAdvice?
    var rain: RainAdvice?
    /// False: known but too far ahead to bother you with it.
    var isVisible = true
}

/// Car: go now, or wait because it saves time.
struct LaterAdvice: Equatable, Sendable {
    struct Slot: Equatable, Sendable {
        let offsetMinutes: Int
        let minutes: Int
    }
    var slots: [Slot]
    /// Nil: go now.
    var waitMinutes: Int?
    var savesMinutes = 0
}

/// Bike: whether it stays dry on the way.
struct RainAdvice: Equatable, Sendable {
    /// Rain starts this many minutes from now.
    var startsInMinutes: Int?
    /// It is dry again this many minutes from now; nil if not within the forecast.
    var dryInMinutes: Int?
}

/// Combines the calendar and settings into one trip, and the providers' answers into one output.
/// No clock, network or storage of its own: everything comes in as an argument.
enum DepartureEngine {
    /// Events further ahead than this don't ask the providers anything yet.
    static let lookahead: TimeInterval = 3 * 3600
    /// Show the leave moment from this long before it.
    static let showBeforeLeave = 45
    /// On the way home: how long after the last event ends the trip stays.
    static let homeGrace: TimeInterval = 45 * 60
    /// What counts as having arrived in time.
    static let arrivalMargin: TimeInterval = 5 * 60
    static let tightMinutes = 5
    static let tightDelay = 3
    static let seriousDelay = 10
    /// Waiting has to save at least this much to be worth saying.
    static let worthWaiting = 10

    // MARK: - Which trip

    static func plan(now: Date, events: [TravelEvent], settings: DepartureSettings, calendar: Calendar) -> TripPlan? {
        guard let home = settings.home else { return nil }
        let located = events
            .filter { !$0.isAllDay && EventLocation.isPhysical($0.location) }
            .sorted { $0.start < $1.start }

        if settings.outbound, let trip = outbound(now: now, located: located, home: home, settings: settings) {
            return trip
        }
        if settings.returnHome {
            return homeward(now: now, located: located, home: home, settings: settings, calendar: calendar)
        }
        return nil
    }

    private static func place(of event: TravelEvent) -> TravelPlace {
        TravelPlace(name: event.location ?? "", latitude: event.latitude, longitude: event.longitude)
    }

    private static func samePlace(_ a: TravelPlace, _ b: TravelPlace) -> Bool {
        if let aLat = a.latitude, let aLon = a.longitude, let bLat = b.latitude, let bLon = b.longitude {
            // About 150 m: the same building, whatever it is called.
            return abs(aLat - bLat) < 0.0015 && abs(aLon - bLon) < 0.0022
        }
        return EventLocation.key(a.name) == EventLocation.key(b.name)
    }

    private static func outbound(now: Date, located: [TravelEvent], home: TravelPlace, settings: DepartureSettings) -> TripPlan? {
        guard let next = located.first(where: { $0.start > now && $0.start.timeIntervalSince(now) <= lookahead }) else {
            return nil
        }
        // Where you are by then: the event you're at, or the one that just ended; otherwise home.
        let before = located.last { $0.id != next.id && $0.start <= now && $0.end.addingTimeInterval(lookahead) > now }
        let origin = before.map(place(of:)) ?? home
        let destination = place(of: next)
        // The next lesson in the same building isn't a trip.
        guard !samePlace(origin, destination) else { return nil }
        return TripPlan(kind: .event, eventID: next.id, title: next.title, origin: origin, destination: destination,
                        mode: settings.mode(for: next.location), arriveBy: next.start, earliestLeave: nil)
    }

    private static func homeward(now: Date, located: [TravelEvent], home: TravelPlace, settings: DepartureSettings,
                                 calendar: Calendar) -> TripPlan? {
        // Overlapping events: the one that ends last is the one you leave from.
        let current = located
            .filter { event in
                let opens = event.end.addingTimeInterval(-Double(settings.showBeforeEndMinutes) * 60)
                return opens <= now && now < event.end.addingTimeInterval(homeGrace)
            }
            .max { $0.end < $1.end }
        guard let last = current else { return nil }
        // Anything with a location that goes on after this one, the same day: not the way home yet.
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last.start)) ?? last.end
        let moreToday = located.contains { $0.id != last.id && $0.end > last.end && $0.start < dayEnd }
        guard !moreToday else { return nil }
        let origin = place(of: last)
        guard !samePlace(origin, home) else { return nil }
        return TripPlan(kind: .home, eventID: last.id, title: last.title, origin: origin, destination: home,
                        mode: settings.mode(for: last.location), arriveBy: nil, earliestLeave: last.end)
    }

    /// The next moment `plan` can give another answer, so nothing has to run until then.
    static func nextWake(after now: Date, events: [TravelEvent], settings: DepartureSettings, calendar: Calendar) -> Date? {
        guard settings.home != nil else { return nil }
        var moments: [Date] = []
        for event in events where !event.isAllDay && EventLocation.isPhysical(event.location) {
            moments.append(event.start.addingTimeInterval(-lookahead))
            moments.append(event.start)
            moments.append(event.end.addingTimeInterval(-Double(settings.showBeforeEndMinutes) * 60))
            moments.append(event.end.addingTimeInterval(homeGrace))
        }
        // A new day has new events.
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            moments.append(midnight)
        }
        return moments.filter { $0 > now }.min()
    }

    /// How often the providers are asked while a trip is on: more often as leaving comes closer.
    static func refreshInterval(minutesUntilLeave: Int) -> TimeInterval {
        if minutesUntilLeave > 45 { return 15 * 60 }
        if minutesUntilLeave > 15 { return 5 * 60 }
        return 2 * 60
    }

    // MARK: - Which option

    /// Puts the providers' answers together. `later` and `rain` are nil when not asked for.
    static func resolve(plan: TripPlan, options: [TravelOption], later: LaterAdvice? = nil, rainForecast: RainForecast? = nil,
                        now: Date) -> DepartureOutput {
        let chosen = choose(plan: plan, options: options, now: now)
        var output = DepartureOutput(plan: plan, chosen: chosen)
        output.later = later

        guard let chosen else {
            output.isVisible = isVisible(plan: plan, leave: nil, now: now)
            return output
        }

        let until = Int((chosen.departure.timeIntervalSince(now) / 60).rounded(.up))
        output.minutesUntilLeave = max(0, until)
        output.alternatives = alternatives(chosen: chosen, options: options, now: now)
        if let arriveBy = plan.arriveBy, chosen.arrival > arriveBy {
            output.isLate = true
        }
        output.timeUrgency = output.isLate ? .serious : until <= tightMinutes ? .tight : .normal
        output.delayUrgency = delayUrgency(chosen)
        output.isVisible = isVisible(plan: plan, leave: chosen.departure, now: now)
        if let rainForecast {
            output.rain = rainAdvice(rainForecast, leave: max(now, chosen.departure), minutes: chosen.minutes, now: now)
        }
        return output
    }

    private static func choose(plan: TripPlan, options: [TravelOption], now: Date) -> TravelOption? {
        let reachable = options
            .filter { !$0.isCancelled && $0.departure >= now.addingTimeInterval(-60) }
            .filter { option in plan.earliestLeave.map { option.departure >= $0.addingTimeInterval(-60) } ?? true }
            .sorted { $0.departure < $1.departure }
        if let arriveBy = plan.arriveBy {
            // The latest that still makes it; if nothing does, the soonest.
            return reachable.last { $0.arrival <= arriveBy.addingTimeInterval(-arrivalMargin) }
                ?? reachable.last { $0.arrival <= arriveBy }
                ?? reachable.first
        }
        return reachable.first
    }

    private static func alternatives(chosen: TravelOption, options: [TravelOption], now: Date) -> [TravelOption] {
        // Cancelled ones stay: you want to know that train isn't coming.
        let others = options
            .filter { $0 != chosen && $0.departure >= chosen.departure.addingTimeInterval(-60) && $0.departure >= now }
            .sorted { $0.departure < $1.departure }
        return Array(([chosen] + others).prefix(3))
    }

    private static func delayUrgency(_ option: TravelOption) -> DepartureOutput.Urgency {
        let delay = max(option.delayMinutes, option.trafficMinutes)
        if option.legs.contains(where: \.isCancelled) || delay >= seriousDelay { return .serious }
        return delay >= tightDelay ? .tight : .normal
    }

    private static func isVisible(plan: TripPlan, leave: Date?, now: Date) -> Bool {
        guard plan.kind == .event else { return true }
        // Without an answer: fall back on the event itself being near.
        let moment = leave ?? plan.arriveBy ?? now
        return moment.timeIntervalSince(now) <= Double(showBeforeLeave) * 60
    }

    // MARK: - Advice

    /// `minutes[offset]`: the trip if you leave that many minutes from now. Offset 0 is now.
    static func laterAdvice(minutes: [Int: Int], plan: TripPlan, now: Date) -> LaterAdvice? {
        guard let nowMinutes = minutes[0] else { return nil }
        let slots = minutes.sorted { $0.key < $1.key }.map { LaterAdvice.Slot(offsetMinutes: $0.key, minutes: $0.value) }
        var advice = LaterAdvice(slots: slots)
        // Only worth saying if it saves time and you still get there on time.
        let useful = slots.filter { slot in
            guard slot.offsetMinutes > 0, nowMinutes - slot.minutes >= worthWaiting else { return false }
            guard let arriveBy = plan.arriveBy else { return true }
            let arrival = now.addingTimeInterval(Double(slot.offsetMinutes + slot.minutes) * 60)
            return arrival <= arriveBy
        }
        if let best = useful.min(by: { $0.minutes < $1.minutes }) {
            advice.waitMinutes = best.offsetMinutes
            advice.savesMinutes = nowMinutes - best.minutes
        }
        return advice
    }

    /// A shower while you'd be on the bike, and when it is over.
    static func rainAdvice(_ forecast: RainForecast, leave: Date, minutes: Int, now: Date) -> RainAdvice {
        let wet = { (point: RainForecast.Point) in point.millimetresPerHour >= 0.1 }
        let arrive = leave.addingTimeInterval(Double(minutes) * 60)
        let during = forecast.points.filter { $0.time >= leave.addingTimeInterval(-300) && $0.time <= arrive }
        guard let start = during.first(where: wet) else { return RainAdvice() }
        let dry = forecast.points.first { $0.time > start.time && !wet($0) }
        func minutesFromNow(_ date: Date) -> Int { max(0, Int((date.timeIntervalSince(now) / 60).rounded())) }
        return RainAdvice(startsInMinutes: minutesFromNow(start.time), dryInMinutes: dry.map { minutesFromNow($0.time) })
    }

    /// wisp has no bike route from MapKit: a walking route's length at this speed.
    static func bikeMinutes(metres: Double, kilometresPerHour: Double = 16) -> Int {
        Int((metres / 1000 / kilometresPerHour * 60).rounded(.up))
    }
}

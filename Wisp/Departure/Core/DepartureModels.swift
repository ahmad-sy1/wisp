import Foundation

/// How you travel. Shown as a switch in the tab, set per trip or as a default in Settings.
enum TravelMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case transit, car, bike
    var id: String { rawValue }
}

/// An address or event location, with its coordinate once it has been looked up.
struct TravelPlace: Codable, Equatable, Hashable, Sendable {
    var name: String
    var latitude: Double?
    var longitude: Double?

    init(name: String, latitude: Double? = nil, longitude: Double? = nil) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    var hasCoordinate: Bool { latitude != nil && longitude != nil }
}

/// A calendar event as the engine sees it.
struct TravelEvent: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    var isAllDay = false
    var location: String?
    /// From the calendar's own map pin, when it has one.
    var latitude: Double?
    var longitude: Double?
    var isRecurring = false
}

/// Settings → Departure.
struct DepartureSettings: Codable, Equatable, Sendable {
    var home: TravelPlace?
    var defaultMode: TravelMode = .transit
    /// Show the trip home this long before the last event ends.
    var showBeforeEndMinutes = 20
    var returnHome = true
    var outbound = true
    var routine = true
    var nowOrLater = true
    var rainCheck = false
    /// The mode you chose for a location, so a repeating event keeps it.
    var modeOverrides: [String: TravelMode] = [:]

    func mode(for location: String?) -> TravelMode {
        location.flatMap { modeOverrides[EventLocation.key($0)] } ?? defaultMode
    }
}

/// One part of a journey: a walk, a train, a bus.
struct TravelLeg: Equatable, Sendable {
    enum Kind: String, Sendable { case walk, rail, bus, tram, metro, ferry, drive, bike }

    var kind: Kind
    /// "NS", "300"; nil for a walk.
    var line: String?
    /// "spoor 3", "halte B".
    var platform: String?
    var departure: Date?
    var minutes: Int
    var delayMinutes = 0
    var isCancelled = false
    /// Where this leg starts, for looking up live times.
    var fromStop: String?
}

/// One way to make the trip.
struct TravelOption: Equatable, Identifiable, Sendable {
    /// When you leave your door, walk to the station included.
    var departure: Date
    var arrival: Date
    var legs: [TravelLeg] = []
    var delayMinutes = 0
    var isCancelled = false
    /// Car: the trip without traffic, to tell how much is lost to it.
    var normalMinutes: Int?
    /// Car: the main road, "A15".
    var routeName: String?

    var id: String { "\(departure.timeIntervalSince1970)-\(arrival.timeIntervalSince1970)" }
    var minutes: Int { Int((arrival.timeIntervalSince(departure) / 60).rounded()) }
    /// Minutes lost to traffic.
    var trafficMinutes: Int {
        guard let normalMinutes else { return 0 }
        return max(0, minutes - normalMinutes)
    }
}

/// Rain in the coming two hours.
struct RainForecast: Equatable, Sendable {
    struct Point: Equatable, Sendable {
        let time: Date
        let millimetresPerHour: Double
    }
    var points: [Point]
}

// MARK: - Protocols

enum TravelError: Error, Equatable, Sendable {
    case missingKey
    case noRoute
    case unavailable
}

/// One per way of travelling, so another country or provider never touches the UI.
protocol TravelProvider: Sendable {
    /// Options that leave at or after `departAt`, or arrive by `arriveBy`.
    func options(from: TravelPlace, to: TravelPlace, departAt: Date?, arriveBy: Date?) async throws -> [TravelOption]
}

protocol RainProvider: Sendable {
    func forecast(at place: TravelPlace, now: Date) async throws -> RainForecast
}

protocol PlaceLookup: Sendable {
    func place(for text: String) async throws -> TravelPlace?
}

// MARK: - Mocks

/// Answers from a list, for the tests and for `-departureDemo` in Debug builds.
struct MockTravelProvider: TravelProvider {
    var answer: @Sendable (_ departAt: Date?, _ arriveBy: Date?) throws -> [TravelOption]

    func options(from: TravelPlace, to: TravelPlace, departAt: Date?, arriveBy: Date?) async throws -> [TravelOption] {
        try answer(departAt, arriveBy)
    }
}

struct MockRainProvider: RainProvider {
    var answer: RainForecast
    func forecast(at place: TravelPlace, now: Date) async throws -> RainForecast { answer }
}

struct MockPlaceLookup: PlaceLookup {
    func place(for text: String) async throws -> TravelPlace? {
        TravelPlace(name: text, latitude: 51.84, longitude: 5.85)
    }
}

import CoreLocation
import MapKit

private extension TravelPlace {
    var mapItem: MKMapItem? {
        guard let latitude, let longitude else { return nil }
        return MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
    }
}

private struct RouteAnswer: Sendable {
    let seconds: TimeInterval
    let metres: Double
    let name: String
}

@MainActor
private func route(from: TravelPlace, to: TravelPlace, type: MKDirectionsTransportType, leaving: Date?) async throws -> RouteAnswer {
    guard let source = from.mapItem, let destination = to.mapItem else { throw TravelError.noRoute }
    let request = MKDirections.Request()
    request.source = source
    request.destination = destination
    request.transportType = type
    request.departureDate = leaving
    let response = try await MKDirections(request: request).calculate()
    guard let best = response.routes.first else { throw TravelError.noRoute }
    return RouteAnswer(seconds: best.expectedTravelTime, metres: best.distance, name: best.name)
}

/// Driving time with traffic from Apple Maps, and what it would be without.
actor MapKitCarProvider: TravelProvider {
    /// From–to → the trip at night, kept for the day it was asked.
    private var normal: [String: (minutes: Int, day: Date)] = [:]

    func options(from: TravelPlace, to: TravelPlace, departAt: Date?, arriveBy: Date?) async throws -> [TravelOption] {
        let moment = departAt ?? .now
        let answer = try await route(from: from, to: to, type: .automobile, leaving: moment)
        let seconds = answer.seconds
        let leave = departAt ?? arriveBy.map { $0.addingTimeInterval(-seconds - DepartureEngine.arrivalMargin) } ?? moment
        let quiet = await normalMinutes(from: from, to: to)
        return [TravelOption(departure: leave, arrival: leave.addingTimeInterval(seconds),
                             legs: [TravelLeg(kind: .drive, departure: leave, minutes: Int((seconds / 60).rounded()))],
                             normalMinutes: quiet, routeName: Self.roadName(answer.name))]
    }

    /// The trip at three at night stands in for no traffic. Asked once a day per route.
    private func normalMinutes(from: TravelPlace, to: TravelPlace) async -> Int? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let key = "\(from.name)→\(to.name)"
        if let known = normal[key], known.day == today { return known.minutes }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
              let night = calendar.date(bySettingHour: 3, minute: 0, second: 0, of: tomorrow),
              let answer = try? await route(from: from, to: to, type: .automobile, leaving: night)
        else { return nil }
        let minutes = Int((answer.seconds / 60).rounded())
        normal[key] = (minutes, today)
        return minutes
    }

    /// "A15" out of a route name like "A15 / A73"; other names aren't worth the room.
    static func roadName(_ name: String) -> String? {
        let first = name.split(whereSeparator: { $0 == "/" || $0 == "," }).first?.trimmingCharacters(in: .whitespaces) ?? ""
        return first.range(of: #"^[AN][0-9]{1,3}$"#, options: .regularExpression) != nil ? first : nil
    }
}

/// Apple Maps has no cycling directions in this SDK: a walking route's length at bike speed.
struct MapKitBikeProvider: TravelProvider {
    func options(from: TravelPlace, to: TravelPlace, departAt: Date?, arriveBy: Date?) async throws -> [TravelOption] {
        let answer = try await route(from: from, to: to, type: .walking, leaving: nil)
        let minutes = DepartureEngine.bikeMinutes(metres: answer.metres)
        let seconds = Double(minutes) * 60
        let leave = departAt ?? arriveBy.map { $0.addingTimeInterval(-seconds - DepartureEngine.arrivalMargin) } ?? .now
        return [TravelOption(departure: leave, arrival: leave.addingTimeInterval(seconds),
                             legs: [TravelLeg(kind: .bike, departure: leave, minutes: minutes)])]
    }
}

/// Without an NS key: a total time from Apple Maps, where it knows one. No line numbers, no delays.
struct MapKitTransitProvider: TravelProvider {
    func options(from: TravelPlace, to: TravelPlace, departAt: Date?, arriveBy: Date?) async throws -> [TravelOption] {
        guard let seconds = try await Self.eta(from: from, to: to) else { throw TravelError.noRoute }
        let leave = departAt ?? arriveBy.map { $0.addingTimeInterval(-seconds - DepartureEngine.arrivalMargin) } ?? .now
        return [TravelOption(departure: leave, arrival: leave.addingTimeInterval(seconds))]
    }

    @MainActor
    private static func eta(from: TravelPlace, to: TravelPlace) async throws -> TimeInterval? {
        guard let source = from.mapItem, let destination = to.mapItem else { return nil }
        let request = MKDirections.Request()
        request.source = source
        request.destination = destination
        request.transportType = .transit
        return try await MKDirections(request: request).calculateETA().expectedTravelTime
    }
}

/// Addresses and event locations to coordinates, through Apple Maps.
struct MapKitPlaceLookup: PlaceLookup {
    func place(for text: String) async throws -> TravelPlace? {
        try await Self.search(text)
    }

    @MainActor
    private static func search(_ text: String) async throws -> TravelPlace? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        guard let item = try await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let coordinate = item.placemark.coordinate
        return TravelPlace(name: text, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

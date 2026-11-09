import Foundation
import OSLog

/// Door-to-door travel advice from the NS Reisinformatie API (`/api/v3/trips`), which covers
/// buses and trams too. Needs a key from apiportal.ns.nl, kept in the Keychain.
struct NSTravelProvider: TravelProvider {
    private static let log = Logger(subsystem: "com.ahmadalasmi.wisp", category: "ns")

    let key: String
    var transport: any HTTPTransport = URLSessionTransport()

    func options(from: TravelPlace, to: TravelPlace, departAt: Date?, arriveBy: Date?) async throws -> [TravelOption] {
        guard let url = Self.url(from: from, to: to, departAt: departAt, arriveBy: arriveBy) else { throw TravelError.noRoute }
        let request = HTTPRequest(url: url, headers: ["Ocp-Apim-Subscription-Key": key, "Accept": "application/json"])
        let response = try await transport.send(request)
        switch response.status {
        case 200: return try NSTripsParser.parse(response.body, origin: from)
        case 401, 403: throw TravelError.missingKey
        default: throw TravelError.unavailable
        }
    }

    /// Asks for one fixed route, only to see whether NS accepts this key. The gateway checks the
    /// key first and answers 401 or 403 when it is wrong, so any other answer means it passed.
    func checkKey() async -> CredentialCheck {
        let utrecht = TravelPlace(name: "Utrecht Centraal", latitude: 52.0894, longitude: 5.1101)
        let amsterdam = TravelPlace(name: "Amsterdam Centraal", latitude: 52.3791, longitude: 4.9003)
        guard let url = Self.url(from: utrecht, to: amsterdam, departAt: nil, arriveBy: nil) else { return .unreachable }
        let request = HTTPRequest(url: url, headers: ["Ocp-Apim-Subscription-Key": key, "Accept": "application/json"])
        guard let response = try? await transport.send(request) else { return .unreachable }
        if response.status == 401 || response.status == 403 { return .rejected }
        if response.status != 200 {
            let answer = String(decoding: response.body.prefix(300), as: UTF8.self)
            Self.log.notice("NS key check: status \(response.status, privacy: .public), \(answer, privacy: .public)")
        }
        return .accepted
    }

    static func url(from: TravelPlace, to: TravelPlace, departAt: Date?, arriveBy: Date?) -> URL? {
        guard let fromLat = from.latitude, let fromLon = from.longitude,
            let toLat = to.latitude, let toLon = to.longitude,
            var parts = URLComponents(string: "https://gateway.apiportal.ns.nl/reisinformatie-api/api/v3/trips")
        else { return nil }
        let time = arriveBy ?? departAt ?? .now
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/Amsterdam")
        parts.queryItems = [
            URLQueryItem(name: "originLat", value: String(fromLat)),
            URLQueryItem(name: "originLng", value: String(fromLon)),
            URLQueryItem(name: "destinationLat", value: String(toLat)),
            URLQueryItem(name: "destinationLng", value: String(toLon)),
            URLQueryItem(name: "dateTime", value: formatter.string(from: time)),
            URLQueryItem(name: "searchForArrival", value: arriveBy == nil ? "false" : "true"),
        ]
        // A "+" in a query means a space; the time zone offset needs a real one.
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.url
    }
}

enum NSTripsParser {
    private struct Answer: Decodable {
        struct Trip: Decodable {
            let status: String?
            let legs: [Leg]
        }
        struct Leg: Decodable {
            let cancelled: Bool?
            let travelType: String?
            let product: Product?
            let origin: Stop
            let destination: Stop
        }
        struct Product: Decodable {
            let number: String?
            let shortCategoryName: String?
            let operatorName: String?
            let type: String?
        }
        struct Stop: Decodable {
            let name: String?
            let lat: Double?
            let lng: Double?
            let plannedDateTime: String?
            let actualDateTime: String?
            let plannedTrack: String?
            let actualTrack: String?
        }
        let trips: [Trip]
    }

    private static let dates: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter
    }()

    private static func date(_ text: String?) -> Date? { text.flatMap { dates.date(from: $0) } }

    /// `origin`: to add the walk to the first stop when the advice starts at a station.
    static func parse(_ data: Data, origin: TravelPlace? = nil) throws -> [TravelOption] {
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data) else { throw TravelError.unavailable }
        return answer.trips.compactMap { trip in option(trip, origin: origin) }
    }

    private static func option(_ trip: Answer.Trip, origin: TravelPlace?) -> TravelOption? {
        guard let first = trip.legs.first, let last = trip.legs.last,
            var departure = date(first.origin.actualDateTime) ?? date(first.origin.plannedDateTime),
            let arrival = date(last.destination.actualDateTime) ?? date(last.destination.plannedDateTime)
        else { return nil }

        var legs = trip.legs.map(leg)
        // No walk in the advice: the way to the first stop is still part of leaving on time.
        if legs.first?.kind != .walk, let origin, let lat = first.origin.lat, let lng = first.origin.lng,
            let walk = walkMinutes(from: origin, toLatitude: lat, longitude: lng), walk > 0
        {
            departure = departure.addingTimeInterval(-Double(walk) * 60)
            legs.insert(TravelLeg(kind: .walk, departure: departure, minutes: walk), at: 0)
        }

        let delays = legs.map(\.delayMinutes)
        let cancelled = trip.status == "CANCELLED" || trip.status == "NOT_POSSIBLE" || legs.contains(where: \.isCancelled)
        return TravelOption(
            departure: departure, arrival: arrival, legs: legs,
            delayMinutes: delays.max() ?? 0, isCancelled: cancelled)
    }

    private static func leg(_ leg: Answer.Leg) -> TravelLeg {
        let planned = date(leg.origin.plannedDateTime)
        let actual = date(leg.origin.actualDateTime)
        let arrival = date(leg.destination.actualDateTime) ?? date(leg.destination.plannedDateTime)
        let start = actual ?? planned
        let minutes = start.flatMap { from in arrival.map { Int(($0.timeIntervalSince(from) / 60).rounded()) } } ?? 0
        let delay = planned.flatMap { p in actual.map { Int(($0.timeIntervalSince(p) / 60).rounded()) } } ?? 0
        let type = (leg.product?.type ?? "").uppercased()
        let category = (leg.product?.shortCategoryName ?? "").uppercased()

        let kind: TravelLeg.Kind
        if leg.travelType == "WALK" || leg.travelType == "TRANSFER" || type == "WALK" {
            kind = .walk
        } else if type == "BUS" || category == "BUS" {
            kind = .bus
        } else if type == "TRAM" || category == "TRAM" {
            kind = .tram
        } else if type == "METRO" || category == "METRO" {
            kind = .metro
        } else if type == "FERRY" || category == "VEER" {
            kind = .ferry
        } else {
            kind = .rail
        }

        let line: String? =
            switch kind {
            case .walk: nil
            // A train's number means nothing to you; its operator and track do.
            case .rail: leg.product?.operatorName == "NS" || leg.product?.operatorName == nil ? "NS" : leg.product?.operatorName
            default: leg.product?.number
            }
        return TravelLeg(
            kind: kind, line: line, platform: leg.origin.actualTrack ?? leg.origin.plannedTrack,
            departure: start, minutes: minutes, delayMinutes: max(0, delay),
            isCancelled: leg.cancelled ?? false, fromStop: leg.origin.name)
    }

    /// As the crow flies times 1.3, at 5 km/h.
    static func walkMinutes(from origin: TravelPlace, toLatitude latitude: Double, longitude: Double) -> Int? {
        guard let fromLat = origin.latitude, let fromLon = origin.longitude else { return nil }
        let metresPerDegree = 111_320.0
        let dy = (latitude - fromLat) * metresPerDegree
        let dx = (longitude - fromLon) * metresPerDegree * cos(fromLat * .pi / 180)
        let metres = (dx * dx + dy * dy).squareRoot() * 1.3
        return Int((metres / 5000 * 60).rounded(.up))
    }
}

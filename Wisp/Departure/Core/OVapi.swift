import Foundation

/// Live bus and tram times from OVapi (v0.ovapi.nl, community run, no key, HTTP only). It adds
/// the delay of a bus leg to the advice from NS. Only stop codes are sent, never an address.
actor OVapiLiveTimes {
    private let transport: any HTTPTransport
    private let base = URL(string: "http://v0.ovapi.nl")!
    private var stops: [String: String]?

    init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    /// Fills in delays and cancellations. Anything going wrong leaves the option as it was.
    func enrich(_ option: TravelOption, now: Date) async -> TravelOption {
        var result = option
        for (index, leg) in option.legs.enumerated() where [.bus, .tram, .metro].contains(leg.kind) {
            guard let stop = leg.fromStop, let line = leg.line, let planned = leg.departure,
                planned.timeIntervalSince(now) < 90 * 60,
                let pass = await pass(stop: stop, line: line, near: planned)
            else { continue }
            result.legs[index].delayMinutes = max(0, pass.delayMinutes)
            result.legs[index].isCancelled = pass.isCancelled
        }
        result.delayMinutes = result.legs.map(\.delayMinutes).max() ?? 0
        result.isCancelled = result.isCancelled || result.legs.contains(where: \.isCancelled)
        return result
    }

    private func pass(stop: String, line: String, near planned: Date) async -> OVapiParser.Pass? {
        do {
            if stops == nil {
                let response = try await transport.send(HTTPRequest(url: base.appendingPathComponent("stopareacode")))
                stops = try OVapiParser.stopIndex(response.body)
            }
            guard let code = stops?[OVapiParser.normalize(stop)] else { return nil }
            let response = try await transport.send(HTTPRequest(url: base.appendingPathComponent("stopareacode/\(code)")))
            return try OVapiParser.passes(response.body).first {
                $0.line == line && abs($0.planned.timeIntervalSince(planned)) < 180
            }
        } catch {
            return nil
        }
    }
}

enum OVapiParser {
    struct Pass: Equatable {
        let line: String
        let planned: Date
        let delayMinutes: Int
        let isCancelled: Bool
    }

    static func normalize(_ name: String) -> String { EventLocation.key(name) }

    /// Stop name → stop area code.
    static func stopIndex(_ data: Data) throws -> [String: String] {
        struct Area: Decodable {
            let TimingPointName: String?
            let TimingPointTown: String?
            let StopAreaCode: String?
        }
        guard let areas = try? JSONDecoder().decode([String: Area].self, from: data) else { throw TravelError.unavailable }
        var index: [String: String] = [:]
        for area in areas.values {
            guard let code = area.StopAreaCode, let name = area.TimingPointName else { continue }
            index[normalize(name)] = code
            if let town = area.TimingPointTown { index[normalize("\(town), \(name)")] = code }
        }
        return index
    }

    private static let dates: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Amsterdam")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    static func passes(_ data: Data) throws -> [Pass] {
        struct Stop: Decodable {
            struct Item: Decodable {
                let LinePublicNumber: String?
                let TargetDepartureTime: String?
                let ExpectedDepartureTime: String?
                let TripStopStatus: String?
            }
            let Passes: [String: Item]?
        }
        guard let areas = try? JSONDecoder().decode([String: [String: Stop]].self, from: data) else {
            throw TravelError.unavailable
        }
        var result: [Pass] = []
        for stops in areas.values {
            for item in stops.values.flatMap({ ($0.Passes ?? [:]).values }) {
                guard let line = item.LinePublicNumber, let target = item.TargetDepartureTime.flatMap(dates.date(from:))
                else { continue }
                let expected = item.ExpectedDepartureTime.flatMap(dates.date(from:)) ?? target
                result.append(
                    Pass(
                        line: line, planned: target,
                        delayMinutes: Int((expected.timeIntervalSince(target) / 60).rounded()),
                        isCancelled: item.TripStopStatus == "CANCEL"))
            }
        }
        return result.sorted { $0.planned < $1.planned }
    }
}

/// NS for the route, OVapi for how late the bus is.
struct TransitProvider: TravelProvider {
    let route: any TravelProvider
    let live: OVapiLiveTimes

    func options(from: TravelPlace, to: TravelPlace, departAt: Date?, arriveBy: Date?) async throws -> [TravelOption] {
        let options = try await route.options(from: from, to: to, departAt: departAt, arriveBy: arriveBy)
        var result: [TravelOption] = []
        for option in options { result.append(await live.enrich(option, now: .now)) }
        return result
    }
}

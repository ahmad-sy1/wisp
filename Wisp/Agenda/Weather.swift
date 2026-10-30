import Foundation

/// The place the weather is for, chosen in Settings (no location permission needed).
struct WeatherPlace: Codable, Hashable, Sendable {
    var name: String
    var detail: String
    var latitude: Double
    var longitude: Double

    static let nijmegen = WeatherPlace(name: "Nijmegen", detail: "Gelderland, Nederland",
                                       latitude: 51.8426, longitude: 5.8528)
}

/// Current weather and the rain forecast for the coming hours.
struct WeatherReport: Equatable, Sendable {
    let temperature: Double
    let code: Int
    let isDay: Bool
    /// Hourly forecast from the current hour on.
    let hours: [WeatherHour]
    let low: Double?
    let high: Double?
    let fetched: Date

    var description: String { WeatherCode.description(code) }
    var symbol: String { WeatherCode.symbol(code, isDay: isDay) }

    /// "Dry until 22:00", "Rain until 15:00", "Dry for the coming hours".
    func rainSummary(at now: Date) -> String {
        let ahead = hours.filter { $0.start.addingTimeInterval(3600) > now }
        guard let first = ahead.first else { return description.capitalizedFirst }
        if first.wet {
            if let dry = ahead.first(where: { !$0.wet }) { return String(localized: "Rain until \(dry.start.clockTime)") }
            return String(localized: "Rain for the coming hours")
        }
        if let wet = ahead.first(where: { $0.wet }) { return String(localized: "Dry until \(wet.start.clockTime)") }
        return String(localized: "Dry for the coming hours")
    }
}

/// One forecast hour: when it starts and whether it is wet.
struct WeatherHour: Equatable, Sendable {
    let start: Date
    let wet: Bool
}

/// Weather from Open-Meteo (free, no key). Fetched only when the Agenda tab opens and
/// the last answer is older than 15 minutes; nothing runs in the background.
@MainActor
final class WeatherStore: ObservableObject {
    static let shared = WeatherStore()

    enum Status: Equatable { case idle, loading, failed }

    @Published private(set) var report: WeatherReport?
    @Published private(set) var status: Status = .idle
    @Published private(set) var place: WeatherPlace {
        didSet {
            if let data = try? JSONEncoder().encode(place) { defaults.set(data, forKey: Key.place) }
        }
    }

    private let defaults = UserDefaults.standard
    private var task: Task<Void, Never>?
    private static let maxAge: TimeInterval = 15 * 60
    /// A forecast hour counts as wet from this chance of rain or this much rain.
    private static let wetChance = 50
    private static let wetMillimetres = 0.2

    private enum Key { static let place = "weatherPlace" }

    private init() {
        place = defaults.data(forKey: Key.place)
            .flatMap { try? JSONDecoder().decode(WeatherPlace.self, from: $0) } ?? .nijmegen
    }

    /// Refreshes unless the last report is recent enough.
    func refreshIfStale() {
        if let report, Date.now.timeIntervalSince(report.fetched) < Self.maxAge { return }
        refresh()
    }

    func setPlace(_ new: WeatherPlace) {
        guard new != place else { return }
        place = new
        report = nil
        refresh()
    }

    /// Looks up places by name for Settings (Open-Meteo geocoding).
    func search(_ name: String) async -> [WeatherPlace] {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, var url = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        else { return [] }
        url.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "count", value: "5"),
            URLQueryItem(name: "language", value: "nl"),
        ]
        guard let request = url.url,
              let result = try? await URLSession.shared.data(from: request),
              let answer = try? JSONDecoder().decode(GeocodingAnswer.self, from: result.0)
        else { return [] }
        return (answer.results ?? []).map {
            WeatherPlace(name: $0.name,
                         detail: [$0.admin1, $0.country].compactMap { $0 }.joined(separator: ", "),
                         latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    private func refresh() {
        task?.cancel()
        status = .loading
        let place = place
        task = Task {
            let report = await Self.fetch(place)
            guard !Task.isCancelled else { return }
            if let report {
                self.report = report
                self.status = .idle
            } else {
                self.status = .failed
            }
        }
    }

    private static func fetch(_ place: WeatherPlace) async -> WeatherReport? {
        guard var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast") else { return nil }
        url.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "precipitation_probability,precipitation"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "forecast_days", value: "2"),
        ]
        guard let request = url.url,
              let result = try? await URLSession.shared.data(from: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let answer = try? JSONDecoder().decode(ForecastAnswer.self, from: result.0)
        else { return nil }

        let now = Date.now
        var hours: [WeatherHour] = []
        for (i, time) in answer.hourly.time.enumerated() {
            let start = Date(timeIntervalSince1970: time)
            // From the current hour up to 18 hours ahead is all the cards need.
            guard start.addingTimeInterval(3600) > now, start < now.addingTimeInterval(18 * 3600) else { continue }
            let chance = answer.hourly.precipitation_probability[safe: i].flatMap { $0 } ?? 0
            let amount = answer.hourly.precipitation[safe: i].flatMap { $0 } ?? 0
            hours.append(WeatherHour(start: start, wet: chance >= wetChance || amount >= wetMillimetres))
        }
        return WeatherReport(
            temperature: answer.current.temperature_2m,
            code: answer.current.weather_code,
            isDay: answer.current.is_day == 1,
            hours: hours,
            low: answer.daily?.temperature_2m_min.first.flatMap { $0 },
            high: answer.daily?.temperature_2m_max.first.flatMap { $0 },
            fetched: now
        )
    }
}

// MARK: - Open-Meteo answers

// Field names follow the API (https://open-meteo.com/en/docs).
private struct ForecastAnswer: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
        let is_day: Int
    }
    struct Hourly: Decodable {
        let time: [Double]
        let precipitation_probability: [Int?]
        let precipitation: [Double?]
    }
    struct Daily: Decodable {
        let temperature_2m_max: [Double?]
        let temperature_2m_min: [Double?]
    }
    let current: Current
    let hourly: Hourly
    let daily: Daily?
}

private struct GeocodingAnswer: Decodable {
    struct Result: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let country: String?
        let admin1: String?
    }
    let results: [Result]?
}

// MARK: - WMO weather codes

/// Open-Meteo reports the weather as a WMO code (https://open-meteo.com/en/docs#weathervariables).
enum WeatherCode {
    static func description(_ code: Int) -> String {
        switch code {
        case 0: String(localized: "clear")
        case 1: String(localized: "mostly clear")
        case 2: String(localized: "partly cloudy")
        case 3: String(localized: "cloudy")
        case 45, 48: String(localized: "fog")
        case 51, 53, 55: String(localized: "drizzle")
        case 56, 57, 66, 67: String(localized: "freezing rain")
        case 61: String(localized: "light rain")
        case 63: String(localized: "rain")
        case 65: String(localized: "heavy rain")
        case 71, 73, 75, 77: String(localized: "snow")
        case 80, 81: String(localized: "showers")
        case 82: String(localized: "heavy showers")
        case 85, 86: String(localized: "snow showers")
        case 95: String(localized: "thunderstorm")
        case 96, 99: String(localized: "thunderstorm with hail")
        default: String(localized: "unknown")
        }
    }

    static func symbol(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun.max" : "moon.stars"
        case 1: isDay ? "sun.max" : "moon"
        case 2: isDay ? "cloud.sun" : "cloud.moon"
        case 3: "cloud"
        case 45, 48: "cloud.fog"
        case 51, 53, 55: "cloud.drizzle"
        case 56, 57, 66, 67: "cloud.sleet"
        case 61, 63: "cloud.rain"
        case 65, 82: "cloud.heavyrain"
        case 71, 73, 75, 77, 85, 86: "cloud.snow"
        case 80, 81: isDay ? "cloud.sun.rain" : "cloud.moon.rain"
        case 95: "cloud.bolt"
        case 96, 99: "cloud.bolt.rain"
        default: "cloud"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

extension String {
    /// "partly cloudy" → "Partly cloudy".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

import Foundation

/// Radar forecast for the Netherlands and Belgium, five minutes at a time for two hours.
/// Free for non-commercial use with a mention of Buienradar; only the rounded coordinate is sent.
struct BuienradarProvider: RainProvider {
    var transport: any HTTPTransport = URLSessionTransport()

    func forecast(at place: TravelPlace, now: Date) async throws -> RainForecast {
        guard let lat = place.latitude, let lon = place.longitude,
            let url = URL(string: String(format: "https://gpsgadget.buienradar.nl/data/raintext?lat=%.2f&lon=%.2f", lat, lon))
        else { throw TravelError.unavailable }
        let response = try await transport.send(HTTPRequest(url: url))
        guard response.status == 200, let text = String(data: response.body, encoding: .utf8) else { throw TravelError.unavailable }
        let forecast = RainParser.buienradar(text, now: now)
        guard !forecast.points.isEmpty else { throw TravelError.unavailable }
        return forecast
    }
}

/// Everywhere else: Open-Meteo's quarter-hourly forecast, a service wisp already uses.
struct OpenMeteoRainProvider: RainProvider {
    var transport: any HTTPTransport = URLSessionTransport()

    func forecast(at place: TravelPlace, now: Date) async throws -> RainForecast {
        guard let lat = place.latitude, let lon = place.longitude,
            let url = URL(
                string: String(
                    format:
                        "https://api.open-meteo.com/v1/forecast?latitude=%.2f&longitude=%.2f&minutely_15=precipitation&forecast_minutely_15=12&timeformat=unixtime",
                    lat, lon))
        else { throw TravelError.unavailable }
        let response = try await transport.send(HTTPRequest(url: url))
        guard response.status == 200 else { throw TravelError.unavailable }
        return try RainParser.openMeteo(response.body)
    }
}

/// The first that answers.
struct FallbackRainProvider: RainProvider {
    let providers: [any RainProvider]

    func forecast(at place: TravelPlace, now: Date) async throws -> RainForecast {
        for provider in providers {
            if let forecast = try? await provider.forecast(at: place, now: now) { return forecast }
        }
        throw TravelError.unavailable
    }
}

enum RainParser {
    /// Lines of `077|15:05`: a value from 0 to 255 where mm/h = 10^((value − 109) / 32).
    /// Times have no date; they run on from now, in Dutch time, also past midnight.
    static func buienradar(_ text: String, now: Date) -> RainForecast {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam") ?? .current
        var points: [RainForecast.Point] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "|")
            guard parts.count == 2, let value = Int(parts[0].trimmingCharacters(in: .whitespaces)) else { continue }
            let clock = parts[1].trimmingCharacters(in: .whitespaces).split(separator: ":").compactMap { Int($0) }
            guard clock.count == 2,
                var time = calendar.date(bySettingHour: clock[0], minute: clock[1], second: 0, of: now)
            else { continue }
            // Half a day behind: that is tomorrow's early morning.
            if time.timeIntervalSince(now) < -12 * 3600 { time = time.addingTimeInterval(24 * 3600) }
            let rain = value == 0 ? 0 : pow(10, (Double(value) - 109) / 32)
            points.append(.init(time: time, millimetresPerHour: rain))
        }
        return RainForecast(points: points)
    }

    static func openMeteo(_ data: Data) throws -> RainForecast {
        struct Answer: Decodable {
            struct Quarter: Decodable {
                let time: [Double]
                let precipitation: [Double?]
            }
            let minutely_15: Quarter
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data) else { throw TravelError.unavailable }
        let quarter = answer.minutely_15
        let points = zip(quarter.time, quarter.precipitation).map { time, amount in
            // Millimetres in a quarter of an hour → per hour.
            RainForecast.Point(time: Date(timeIntervalSince1970: time), millimetresPerHour: (amount ?? 0) * 4)
        }
        return RainForecast(points: points)
    }
}

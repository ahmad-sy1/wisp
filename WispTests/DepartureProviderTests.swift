import XCTest

private let amsterdam = TimeZone(identifier: "Europe/Amsterdam")!

private func at(_ hour: Int, _ minute: Int = 0, day: Int = 5) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = amsterdam
    return calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

/// Hand-written after the documented shape of the v3 API: there is no key to fetch a real one with.
private let nsTrip = """
{"trips":[{"status":"NORMAL","legs":[
 {"travelType":"WALK","cancelled":false,"product":{"type":"WALK"},
  "origin":{"name":"Thuis","plannedDateTime":"2026-11-05T15:36:00+0100"},
  "destination":{"name":"Nijmegen","plannedDateTime":"2026-11-05T15:42:00+0100"}},
 {"travelType":"PUBLIC_TRANSIT","cancelled":false,
  "product":{"number":"3045","shortCategoryName":"SPR","operatorName":"NS","type":"TRAIN"},
  "origin":{"name":"Nijmegen","plannedDateTime":"2026-11-05T15:42:00+0100","actualDateTime":"2026-11-05T15:46:00+0100","plannedTrack":"3","actualTrack":"4"},
  "destination":{"name":"Arnhem","plannedDateTime":"2026-11-05T15:58:00+0100"}},
 {"travelType":"PUBLIC_TRANSIT","cancelled":false,
  "product":{"number":"300","shortCategoryName":"Bus","operatorName":"Breng","type":"BUS"},
  "origin":{"name":"Arnhem, Centraal","plannedDateTime":"2026-11-05T16:04:00+0100","plannedTrack":"B"},
  "destination":{"name":"Thuis","plannedDateTime":"2026-11-05T16:21:00+0100"}}
]}]}
"""

final class NSTripsTests: XCTestCase {
    func testParsesLegsWithLinesAndPlatforms() throws {
        let option = try XCTUnwrap(NSTripsParser.parse(Data(nsTrip.utf8)).first)
        XCTAssertEqual(option.departure, at(15, 36))
        XCTAssertEqual(option.arrival, at(16, 21))
        XCTAssertEqual(option.legs.map(\.kind), [.walk, .rail, .bus])
        XCTAssertEqual(option.legs[0].minutes, 6)
        XCTAssertEqual(option.legs[1].line, "NS")
        XCTAssertEqual(option.legs[1].platform, "4", "the actual track wins")
        XCTAssertEqual(option.legs[1].delayMinutes, 4)
        XCTAssertEqual(option.legs[2].line, "300")
        XCTAssertEqual(option.legs[2].platform, "B")
        XCTAssertEqual(option.delayMinutes, 4)
        XCTAssertFalse(option.isCancelled)
    }

    func testCancelledTrip() throws {
        let text = nsTrip.replacingOccurrences(of: #""status":"NORMAL""#, with: #""status":"CANCELLED""#)
        XCTAssertEqual(try NSTripsParser.parse(Data(text.utf8)).first?.isCancelled, true)
    }

    func testAddsTheWalkWhenTheAdviceStartsAtAStation() throws {
        let text = """
        {"trips":[{"legs":[{"travelType":"PUBLIC_TRANSIT","product":{"type":"TRAIN"},
         "origin":{"lat":51.843,"lng":5.853,"plannedDateTime":"2026-11-05T15:42:00+0100"},
         "destination":{"plannedDateTime":"2026-11-05T15:58:00+0100"}}]}]}
        """
        let home = TravelPlace(name: "Thuis", latitude: 51.835, longitude: 5.853)
        let option = try XCTUnwrap(NSTripsParser.parse(Data(text.utf8), origin: home).first)
        XCTAssertEqual(option.legs.first?.kind, .walk)
        let walk = try XCTUnwrap(option.legs.first?.minutes)
        XCTAssertEqual(walk, 14, "890 m in a line, about 1160 m on foot")
        XCTAssertEqual(option.departure, at(15, 42).addingTimeInterval(-Double(walk) * 60))
    }

    func testBadAnswerIsAnErrorNotACrash() {
        XCTAssertThrowsError(try NSTripsParser.parse(Data("nope".utf8)))
    }

    func testURLEncodesTheOffset() throws {
        let from = TravelPlace(name: "a", latitude: 51, longitude: 5)
        let url = try XCTUnwrap(NSTravelProvider.url(from: from, to: from, departAt: nil, arriveBy: at(10)))
        XCTAssertTrue(url.absoluteString.contains("dateTime=2026-11-05T10:00:00%2B01:00") || url.absoluteString.contains("2026-11-05T10%3A00%3A00%2B01%3A00"), url.absoluteString)
        XCTAssertTrue(url.absoluteString.contains("searchForArrival=true"))
    }

    func testNoCoordinateNoRequest() {
        XCTAssertNil(NSTravelProvider.url(from: TravelPlace(name: "a"), to: TravelPlace(name: "b"), departAt: nil, arriveBy: nil))
    }

    func testRejectedKeyIsMissingKey() async {
        struct Refuse: HTTPTransport {
            func send(_ request: HTTPRequest) async throws -> HTTPResponse { HTTPResponse(status: 401, headers: [:], body: Data()) }
        }
        let place = TravelPlace(name: "a", latitude: 51, longitude: 5)
        do {
            _ = try await NSTravelProvider(key: "k", transport: Refuse()).options(from: place, to: place, departAt: nil, arriveBy: nil)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? TravelError, .missingKey)
        }
    }
}

final class OVapiTests: XCTestCase {
    private let stops = #"{"nmgbus":{"TimingPointTown":"Nijmegen","TimingPointName":"Nijmegen, Centraal Station","StopAreaCode":"nmgbus"}}"#
    private let passes = """
    {"nmgbus":{"60001005":{"Stop":{},"GeneralMessages":{},"Passes":{
      "a":{"LinePublicNumber":"300","TargetDepartureTime":"2026-11-05T16:04:00","ExpectedDepartureTime":"2026-11-05T16:09:00","TripStopStatus":"DRIVING"},
      "b":{"LinePublicNumber":"33","TargetDepartureTime":"2026-11-05T16:10:00","ExpectedDepartureTime":"2026-11-05T16:10:00","TripStopStatus":"CANCEL"}
    }}}}
    """

    func testIndexAndPasses() throws {
        XCTAssertEqual(try OVapiParser.stopIndex(Data(stops.utf8))["nijmegen centraal station"], "nmgbus")
        let found = try OVapiParser.passes(Data(passes.utf8))
        XCTAssertEqual(found, [
            .init(line: "300", planned: at(16, 4), delayMinutes: 5, isCancelled: false),
            .init(line: "33", planned: at(16, 10), delayMinutes: 0, isCancelled: true),
        ])
    }

    private struct Answers: HTTPTransport {
        let stops: String
        let passes: String
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            HTTPResponse(status: 200, headers: [:], body: Data((request.url.path.hasSuffix("stopareacode") ? stops : passes).utf8))
        }
    }

    private func option(line: String, departure: Date) -> TravelOption {
        TravelOption(departure: departure, arrival: departure.addingTimeInterval(600),
                     legs: [TravelLeg(kind: .bus, line: line, departure: departure, minutes: 10, fromStop: "Nijmegen, Centraal Station")])
    }

    func testEnrichAddsTheDelay() async {
        let live = OVapiLiveTimes(transport: Answers(stops: stops, passes: passes))
        let result = await live.enrich(option(line: "300", departure: at(16, 4)), now: at(15, 50))
        XCTAssertEqual(result.delayMinutes, 5)
        XCTAssertEqual(result.legs[0].delayMinutes, 5)
    }

    func testEnrichMarksCancellation() async {
        let live = OVapiLiveTimes(transport: Answers(stops: stops, passes: passes))
        let result = await live.enrich(option(line: "33", departure: at(16, 10)), now: at(15, 50))
        XCTAssertTrue(result.isCancelled)
    }

    func testFailureLeavesTheOptionAlone() async {
        let live = OVapiLiveTimes(transport: Answers(stops: "garbage", passes: "garbage"))
        let original = option(line: "300", departure: at(16, 4))
        let result = await live.enrich(original, now: at(15, 50))
        XCTAssertEqual(result, original)
    }

    func testFarAheadAsksNothing() async {
        let live = OVapiLiveTimes(transport: Answers(stops: stops, passes: passes))
        let result = await live.enrich(option(line: "300", departure: at(20)), now: at(15))
        XCTAssertEqual(result.delayMinutes, 0)
    }
}

final class RainParserTests: XCTestCase {
    func testBuienradar() {
        let forecast = RainParser.buienradar("000|15:40\n109|15:45\n141|15:50\nbad line\n", now: at(15, 38))
        XCTAssertEqual(forecast.points.map(\.time), [at(15, 40), at(15, 45), at(15, 50)])
        XCTAssertEqual(forecast.points[0].millimetresPerHour, 0)
        XCTAssertEqual(forecast.points[1].millimetresPerHour, 1, accuracy: 0.001)
        XCTAssertEqual(forecast.points[2].millimetresPerHour, 10, accuracy: 0.001)
    }

    func testBuienradarPastMidnight() {
        let forecast = RainParser.buienradar("000|23:55\n000|00:00\n000|00:05\n", now: at(23, 50))
        XCTAssertEqual(forecast.points.map(\.time), [at(23, 55), at(0, 0, day: 6), at(0, 5, day: 6)])
    }

    func testOpenMeteo() throws {
        let body = #"{"minutely_15":{"time":[1000,1900],"precipitation":[0.5,null]}}"#
        let forecast = try RainParser.openMeteo(Data(body.utf8))
        XCTAssertEqual(forecast.points.map(\.millimetresPerHour), [2, 0])
    }

    func testFallbackUsesTheNextOne() async throws {
        struct Broken: RainProvider {
            func forecast(at place: TravelPlace, now: Date) async throws -> RainForecast { throw TravelError.unavailable }
        }
        let good = RainForecast(points: [.init(time: at(10), millimetresPerHour: 1)])
        let provider = FallbackRainProvider(providers: [Broken(), MockRainProvider(answer: good)])
        let answer = try await provider.forecast(at: TravelPlace(name: "x"), now: at(10))
        XCTAssertEqual(answer, good)
    }
}

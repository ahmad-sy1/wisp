import XCTest

private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
    return c
}()

private func at(_ hour: Int, _ minute: Int = 0, day: Int = 5) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

private func event(_ id: String, _ start: Date, _ end: Date, _ location: String? = "Station 1", allDay: Bool = false, recurring: Bool = false) -> TravelEvent {
    TravelEvent(id: id, title: "Les \(id)", start: start, end: end, isAllDay: allDay, location: location, isRecurring: recurring)
}

private let settings: DepartureSettings = {
    var s = DepartureSettings()
    s.home = TravelPlace(name: "Thuis 1")
    return s
}()

private func plan(_ now: Date, _ events: [TravelEvent], _ s: DepartureSettings = settings) -> TripPlan? {
    DepartureEngine.plan(now: now, events: events, settings: s, calendar: calendar)
}

private func option(_ leave: Date, _ minutes: Int, delay: Int = 0, cancelled: Bool = false, normal: Int? = nil) -> TravelOption {
    TravelOption(departure: leave, arrival: leave.addingTimeInterval(Double(minutes) * 60), delayMinutes: delay, isCancelled: cancelled, normalMinutes: normal)
}

final class TripPlanTests: XCTestCase {
    func testNoHomeAddressNoTrip() {
        var s = DepartureSettings()
        s.home = nil
        XCTAssertNil(plan(at(9), [event("a", at(10), at(11))], s))
    }

    func testEventWithoutLocationIsNoTrip() {
        XCTAssertNil(plan(at(9), [event("a", at(10), at(11), nil)]))
        XCTAssertNil(plan(at(9), [event("a", at(10), at(11), "   ")]))
    }

    func testVideoCallsAndLinksAreNoTrip() {
        for location in ["Zoom", "Microsoft Teams", "https://meet.google.com/abc", "www.example.com", "online", "Teams: 123"] {
            XCTAssertFalse(EventLocation.isPhysical(location), location)
        }
        for location in ["Heyendaalseweg 141, Nijmegen", "Teamsportcentrum", "Zoomerhof 4", "Station Nijmegen"] {
            XCTAssertTrue(EventLocation.isPhysical(location), location)
        }
    }

    func testAllDayEventIsNoTrip() {
        XCTAssertNil(plan(at(9), [event("a", at(0), at(23), allDay: true)]))
    }

    func testOutboundWithinLookahead() throws {
        let trip = try XCTUnwrap(plan(at(9), [event("a", at(10), at(11))]))
        XCTAssertEqual(trip.kind, .event)
        XCTAssertEqual(trip.arriveBy, at(10))
        XCTAssertEqual(trip.origin.name, "Thuis 1")
        XCTAssertNil(plan(at(6), [event("a", at(10), at(11))]), "too far ahead")
    }

    func testOutboundSwitchedOff() {
        var s = settings
        s.outbound = false
        XCTAssertNil(plan(at(9), [event("a", at(10), at(11))], s))
    }

    func testNextEventStartsFromTheCurrentOne() throws {
        let trip = try XCTUnwrap(plan(at(10, 30), [event("a", at(10), at(11), "School"), event("b", at(12), at(13), "Werk")]))
        XCTAssertEqual(trip.origin.name, "School")
        XCTAssertEqual(trip.destination.name, "Werk")
    }

    func testSameBuildingIsNoTrip() {
        let events = [event("a", at(10), at(11), "Lokaal, School"), event("b", at(11, 15), at(12), "lokaal school")]
        XCTAssertNil(plan(at(10, 30), events))
    }

    func testSameCoordinateIsNoTrip() {
        var a = event("a", at(10), at(11), "Gebouw A")
        a.latitude = 51.84; a.longitude = 5.85
        var b = event("b", at(11, 15), at(12), "Gebouw B")
        b.latitude = 51.8405; b.longitude = 5.8505
        XCTAssertNil(plan(at(10, 30), [a, b]))
    }

    func testEventAtHomeIsNoTripHome() {
        XCTAssertNil(plan(at(10, 50), [event("a", at(10), at(11), "thuis 1")]))
    }

    func testHomeWindow() throws {
        let events = [event("a", at(14), at(16))]
        XCTAssertNil(plan(at(15, 39), events), "before the 20 minutes")
        let trip = try XCTUnwrap(plan(at(15, 40), events))
        XCTAssertEqual(trip.kind, .home)
        XCTAssertEqual(trip.earliestLeave, at(16))
        XCTAssertNil(trip.arriveBy)
        XCTAssertNotNil(plan(at(16, 30), events), "still there just after")
        XCTAssertNil(plan(at(16, 46), events), "after the grace, you've gone")
    }

    func testHomeWindowFollowsTheSetting() {
        var s = settings
        s.showBeforeEndMinutes = 5
        XCTAssertNil(plan(at(15, 40), [event("a", at(14), at(16))], s))
    }

    func testNotHomeWhileAnotherEventFollows() {
        // b is more than three hours off, so no outbound either.
        let events = [event("a", at(10), at(11), "School"), event("b", at(15), at(16), "Werk")]
        XCTAssertNil(plan(at(10, 50), events))
        XCTAssertEqual(plan(at(15, 50), events)?.kind, .home)
    }

    func testOutboundWinsOverHome() {
        let events = [event("a", at(10), at(11), "School"), event("b", at(12), at(13), "Werk")]
        XCTAssertEqual(plan(at(10, 50), events)?.kind, .event)
    }

    func testOverlappingEventsLeaveFromTheOneThatEndsLast() throws {
        let events = [event("long", at(10), at(16), "School"), event("short", at(11), at(12), "Kantine")]
        XCTAssertNil(plan(at(11, 50), events).flatMap { $0.kind == .home ? $0 : nil }, "the long one goes on")
        let trip = try XCTUnwrap(plan(at(15, 50), events))
        XCTAssertEqual(trip.eventID, "long")
    }

    func testEventOverMidnightStillGoesHome() throws {
        let events = [event("night", at(22), at(0, 30, day: 6))]
        let trip = try XCTUnwrap(plan(at(0, 20, day: 6), events))
        XCTAssertEqual(trip.kind, .home)
        XCTAssertEqual(trip.earliestLeave, at(0, 30, day: 6))
    }

    func testEventJustAfterMidnightIsOutbound() throws {
        let trip = try XCTUnwrap(plan(at(23, 30), [event("x", at(0, 30, day: 6), at(2, day: 6))]))
        XCTAssertEqual(trip.arriveBy, at(0, 30, day: 6))
    }

    func testNextDaysEventDoesntHoldUpTheWayHome() {
        let events = [event("a", at(14), at(16), "School"), event("b", at(9, 0, day: 6), at(10, 0, day: 6), "Werk")]
        XCTAssertEqual(plan(at(15, 50), events)?.kind, .home)
    }

    func testPerLocationModeOverride() {
        var s = settings
        s.modeOverrides[EventLocation.key("Station 1")] = .bike
        XCTAssertEqual(plan(at(9), [event("a", at(10), at(11))], s)?.mode, .bike)
        XCTAssertEqual(plan(at(9), [event("a", at(10), at(11), "Elders")], s)?.mode, .transit)
    }
}

final class NextWakeTests: XCTestCase {
    func testWakesAtTheFirstChange() {
        let events = [event("a", at(14), at(16))]
        let wake = { DepartureEngine.nextWake(after: $0, events: events, settings: settings, calendar: calendar) }
        XCTAssertEqual(wake(at(8)), at(11), "three hours before")
        XCTAssertEqual(wake(at(11)), at(14))
        XCTAssertEqual(wake(at(14)), at(15, 40))
        XCTAssertEqual(wake(at(15, 40)), at(16, 45))
        XCTAssertEqual(wake(at(16, 45)), at(0, 0, day: 6), "midnight: new events")
    }

    func testNoHomeNeverWakes() {
        var s = settings
        s.home = nil
        XCTAssertNil(DepartureEngine.nextWake(after: at(8), events: [event("a", at(14), at(16))], settings: s, calendar: calendar))
    }

    func testRefreshGetsFasterCloserToLeaving() {
        XCTAssertEqual(DepartureEngine.refreshInterval(minutesUntilLeave: 90), 900)
        XCTAssertEqual(DepartureEngine.refreshInterval(minutesUntilLeave: 30), 300)
        XCTAssertEqual(DepartureEngine.refreshInterval(minutesUntilLeave: 5), 120)
    }
}

final class ResolveTests: XCTestCase {
    private let outbound = TripPlan(kind: .event, eventID: "a", title: "Les", origin: TravelPlace(name: "Thuis"),
                                    destination: TravelPlace(name: "School"), mode: .transit, arriveBy: at(10))
    private let home = TripPlan(kind: .home, eventID: "a", title: "Les", origin: TravelPlace(name: "School"),
                                destination: TravelPlace(name: "Thuis"), mode: .transit, earliestLeave: at(16))

    func testOutboundTakesTheLatestThatMakesIt() {
        let options = [option(at(9, 0), 30), option(at(9, 20), 30), option(at(9, 40), 30)]
        let out = DepartureEngine.resolve(plan: outbound, options: options, now: at(9))
        XCTAssertEqual(out.chosen, options[1], "arrives 9:50; the 9:40 arrives right on 10:10")
        XCTAssertEqual(out.minutesUntilLeave, 20)
        XCTAssertFalse(out.isLate)
    }

    func testOutboundFallsBackOnJustInTime() {
        let options = [option(at(9, 20), 40)]
        XCTAssertEqual(DepartureEngine.resolve(plan: outbound, options: options, now: at(9)).chosen, options[0])
    }

    func testOutboundLateIsSerious() {
        let out = DepartureEngine.resolve(plan: outbound, options: [option(at(9, 50), 30)], now: at(9, 40))
        XCTAssertTrue(out.isLate)
        XCTAssertEqual(out.timeUrgency, .serious)
    }

    func testHomeTakesTheFirstAfterTheEnd() {
        let options = [option(at(15, 50), 30), option(at(16, 4), 30), option(at(16, 20), 30)]
        let out = DepartureEngine.resolve(plan: home, options: options, now: at(15, 50))
        XCTAssertEqual(out.chosen, options[1])
        XCTAssertEqual(out.minutesUntilLeave, 14)
    }

    func testCancelledIsSkippedButStaysInTheList() {
        let options = [option(at(16, 4), 30, cancelled: true), option(at(16, 20), 30), option(at(16, 40), 30, cancelled: true)]
        let out = DepartureEngine.resolve(plan: home, options: options, now: at(16))
        XCTAssertEqual(out.chosen, options[1])
        XCTAssertEqual(out.alternatives, [options[1], options[2]])
    }

    func testPastOptionsAreSkipped() {
        var options = [option(at(16, 1), 30), option(at(16, 20), 30)]
        options[0].legs = [TravelLeg(kind: .rail, minutes: 30)]
        options[1].legs = options[0].legs
        XCTAssertEqual(DepartureEngine.resolve(plan: home, options: options, now: at(16, 10)).chosen, options[1])
    }

    func testUrgency() {
        var out = DepartureEngine.resolve(plan: home, options: [option(at(16, 20), 30)], now: at(16))
        XCTAssertEqual(out.timeUrgency, .normal)
        out = DepartureEngine.resolve(plan: home, options: [option(at(16, 3), 30)], now: at(16))
        XCTAssertEqual(out.timeUrgency, .tight)
        out = DepartureEngine.resolve(plan: home, options: [option(at(16, 30), 30, delay: 4)], now: at(16))
        XCTAssertEqual(out.delayUrgency, .tight)
        out = DepartureEngine.resolve(plan: home, options: [option(at(16, 30), 30, delay: 12)], now: at(16))
        XCTAssertEqual(out.delayUrgency, .serious)
        out = DepartureEngine.resolve(plan: home, options: [option(at(16, 30), 57, normal: 42)], now: at(16))
        XCTAssertEqual(out.chosen?.trafficMinutes, 15)
        XCTAssertEqual(out.delayUrgency, .serious, "a jam")
    }

    func testCancelledLegIsSerious() {
        var o = option(at(16, 30), 30)
        o.legs = [TravelLeg(kind: .bus, minutes: 10, isCancelled: true)]
        XCTAssertEqual(DepartureEngine.resolve(plan: home, options: [o], now: at(16)).delayUrgency, .serious)
    }

    func testOutboundFarAheadIsKnownButNotShown() {
        let out = DepartureEngine.resolve(plan: outbound, options: [option(at(9, 20), 30)], now: at(8))
        XCTAssertFalse(out.isVisible)
        XCTAssertTrue(DepartureEngine.resolve(plan: outbound, options: [option(at(9, 20), 30)], now: at(8, 40)).isVisible)
    }

    func testACarRollsAlongWithTheClockButATrainDoesnt() {
        var car = option(at(16), 40)
        car.legs = [TravelLeg(kind: .drive, minutes: 40)]
        let out = DepartureEngine.resolve(plan: home, options: [car], now: at(16, 5))
        XCTAssertEqual(out.chosen?.departure, at(16, 5))
        XCTAssertEqual(out.chosen?.arrival, at(16, 45))
        var train = option(at(16), 40)
        train.legs = [TravelLeg(kind: .rail, minutes: 40)]
        XCTAssertNil(DepartureEngine.resolve(plan: home, options: [train], now: at(16, 5)).chosen)
    }

    func testLeavingTooLateByCarMeansLate() {
        var car = option(at(9), 50)
        car.legs = [TravelLeg(kind: .drive, minutes: 50)]
        let out = DepartureEngine.resolve(plan: outbound, options: [car], now: at(9, 20))
        XCTAssertTrue(out.isLate)
    }

    func testNoOptionsMeansNoAnswerNotACrash() {
        let out = DepartureEngine.resolve(plan: home, options: [], now: at(16))
        XCTAssertNil(out.chosen)
        XCTAssertEqual(out.alternatives, [])
        XCTAssertEqual(out.delayUrgency, .normal)
    }
}

final class AdviceTests: XCTestCase {
    private let home = TripPlan(kind: .home, eventID: "a", title: "Les", origin: TravelPlace(name: "School"),
                                destination: TravelPlace(name: "Thuis"), mode: .car, earliestLeave: at(16))

    func testWaitWhenItClearlySaves() {
        let advice = DepartureEngine.laterAdvice(minutes: [0: 57, 30: 50, 60: 42], plan: home, now: at(16))
        XCTAssertEqual(advice?.waitMinutes, 60)
        XCTAssertEqual(advice?.savesMinutes, 15)
    }

    func testGoNowWhenItDoesntSaveEnough() {
        let advice = DepartureEngine.laterAdvice(minutes: [0: 45, 30: 40, 60: 38], plan: home, now: at(16))
        XCTAssertNil(advice?.waitMinutes)
        XCTAssertEqual(advice?.slots.count, 3)
    }

    func testWaitingMayNotMakeYouLate() {
        var outbound = home
        outbound.arriveBy = at(17)
        let advice = DepartureEngine.laterAdvice(minutes: [0: 57, 30: 40, 60: 30], plan: outbound, now: at(16))
        XCTAssertNil(advice?.waitMinutes, "leaving later arrives 17:10 and 17:30")
    }

    func testRain() {
        let points = stride(from: 0, to: 12, by: 1).map { i in
            RainForecast.Point(time: at(16, i * 5), millimetresPerHour: (2...6).contains(i) ? 1.2 : 0)
        }
        let forecast = RainForecast(points: points)
        let wet = DepartureEngine.rainAdvice(forecast, leave: at(16), minutes: 22, now: at(16))
        XCTAssertEqual(wet.startsInMinutes, 10)
        XCTAssertEqual(wet.dryInMinutes, 35)
        let dry = DepartureEngine.rainAdvice(forecast, leave: at(16), minutes: 5, now: at(16))
        XCTAssertEqual(dry, RainAdvice())
    }

    func testBikeMinutes() {
        XCTAssertEqual(DepartureEngine.bikeMinutes(metres: 4000), 15)
        XCTAssertEqual(DepartureEngine.bikeMinutes(metres: 0), 0)
    }
}

final class RoutineTests: XCTestCase {
    func testThreeDaysAtOnePlaceIsARoutine() {
        let history = (2...4).map { event("l\($0)", at(9, 0, day: $0), at(10, 0, day: $0), "School") }
            .map { TravelEvent(id: $0.id, title: "Wiskunde", start: $0.start, end: $0.end, location: $0.location) }
        XCTAssertEqual(RoutineDetector.routines(history: history, calendar: calendar), ["wiskunde": "School"])
        XCTAssertEqual(RoutineDetector.routines(history: Array(history.prefix(2)), calendar: calendar), [:])
    }

    func testRecurringCountsAtOnce() {
        let e = TravelEvent(id: "a", title: "Dienst", start: at(9), end: at(10), location: "Werk", isRecurring: true)
        XCTAssertEqual(RoutineDetector.routines(history: [e], calendar: calendar), ["dienst": "Werk"])
    }

    func testRoutineFillsInAnEmptyLocationOnly() {
        let empty = TravelEvent(id: "a", title: "Wiskunde!", start: at(9), end: at(10), location: nil)
        let other = TravelEvent(id: "b", title: "Wiskunde", start: at(9), end: at(10), location: "Elders")
        let online = TravelEvent(id: "c", title: "Wiskunde", start: at(9), end: at(10), location: "Zoom")
        let result = RoutineDetector.apply(["wiskunde": "School"], to: [empty, other, online])
        XCTAssertEqual(result.map(\.location), ["School", "Elders", "Zoom"])
    }
}

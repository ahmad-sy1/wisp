import AppKit
import EventKit

/// Runs the departure assistant: reads the calendar, asks the providers while a trip is on, and
/// publishes one `DepartureOutput`.
///
/// Without a home address nothing runs at all. Otherwise there is one pending wake-up: at the
/// next moment the engine says can matter, every minute or so during a trip. Nothing while asleep.
@MainActor
final class DepartureStore: ObservableObject {
    static let shared = DepartureStore()

    @Published var settings: DepartureSettings {
        didSet {
            if !isDemo, let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: Key.settings) }
            if oldValue != settings { evaluate() }
        }
    }

    /// What to show now; nil: no relevant trip, so nothing shows.
    @Published private(set) var output: DepartureOutput?
    @Published private(set) var hasNSKey: Bool

    private let defaults = UserDefaults.standard
    private var isDemo = false
    private var wake: DispatchWorkItem?
    private var refreshing: Task<Void, Never>?
    private var asleep = false
    private var started = false
    private var observers: [NSObjectProtocol] = []

    // What the last answer was, so the countdown can go on without asking again.
    private var currentPlan: TripPlan?
    private var options: [TravelOption] = []
    private var later: LaterAdvice?
    private var laterFetched: Date?
    private var rain: RainForecast?
    private var fetched: Date?
    private var places: [String: TravelPlace] = [:]
    private var routines: [String: String] = [:]
    private var routinesRead: Date?

    private var transit: (any TravelProvider)
    private var car: any TravelProvider = MapKitCarProvider()
    private var bike: any TravelProvider = MapKitBikeProvider()
    private var rainProvider: any RainProvider = FallbackRainProvider(providers: [BuienradarProvider(), OpenMeteoRainProvider()])
    private var lookup: any PlaceLookup = MapKitPlaceLookup()
    private var clock: () -> Date = { .now }
    private var demoEvents: [TravelEvent]?

    private static let keyAccount = "ns-api-key"
    private static let laterMaxAge: TimeInterval = 15 * 60

    private enum Key { static let settings = "departureSettings" }

    private init() {
        settings =
            UserDefaults.standard.data(forKey: Key.settings)
            .flatMap { try? JSONDecoder().decode(DepartureSettings.self, from: $0) } ?? DepartureSettings()
        let key = Keychain.get(Self.keyAccount)
        hasNSKey = key != nil
        transit = Self.transitProvider(key: key)
        Self.migrateOldTravelMode(into: &settings)
    }

    /// Before this page existed, how you travel was set under Calendar & weather.
    private static func migrateOldTravelMode(into settings: inout DepartureSettings) {
        let defaults = UserDefaults.standard
        guard defaults.data(forKey: Key.settings) == nil, let old = defaults.string(forKey: "agendaTravelMode") else { return }
        switch old {
        case "car": settings.defaultMode = .car
        case "transit": settings.defaultMode = .transit
        default: settings.defaultMode = .bike
        }
    }

    private static func transitProvider(key: String?) -> any TravelProvider {
        guard let key else { return MapKitTransitProvider() }
        return TransitProvider(route: NSTravelProvider(key: key), live: OVapiLiveTimes())
    }

    // MARK: - Starting

    func start() {
        guard !started else { return }
        started = true
        observeSystem()
        #if DEBUG
            // `-departureDemo car` (or transit, bike) shows made-up trips, for snapshots and without keys.
            if let demo = UserDefaults.standard.string(forKey: "departureDemo") { return startDemo(demo) }
        #endif
        evaluate()
    }

    /// Settings: looks up the address, then keeps it.
    func setHome(_ address: String) async -> Bool {
        guard let found = try? await lookup.place(for: address), found.hasCoordinate else { return false }
        settings.home = found
        return true
    }

    func search(_ text: String) async -> TravelPlace? {
        try? await lookup.place(for: text)
    }

    /// The switch in the tab: remembered for this location, so a repeating event keeps it.
    func setMode(_ mode: TravelMode) {
        guard let plan = currentPlan else {
            settings.defaultMode = mode
            return
        }
        let place = plan.kind == .home ? plan.origin.name : plan.destination.name
        settings.modeOverrides[EventLocation.key(place)] = mode
    }

    /// The last characters of the stored key, enough to recognise it.
    var nsKeySuffix: String {
        String((Keychain.get(Self.keyAccount) ?? "").suffix(4))
    }

    func setNSKey(_ key: String?) {
        if let key, !key.isEmpty {
            Keychain.set(key, for: Self.keyAccount)
        } else {
            Keychain.remove(Self.keyAccount)
        }
        let stored = Keychain.get(Self.keyAccount)
        hasNSKey = stored != nil
        transit = Self.transitProvider(key: stored)
        fetched = nil
        evaluate()
    }

    // MARK: - Deciding

    /// Looks at the calendar and decides what is next.
    private func evaluate() {
        guard started, !asleep else { return }
        let now = clock()
        let events = readEvents(now: now)
        let found = DepartureEngine.plan(now: now, events: events, settings: settings, calendar: .current)
        var plan = found
        if plan?.eventID != currentPlan?.eventID || plan?.mode != currentPlan?.mode || plan?.kind != currentPlan?.kind {
            options = []
            later = nil
            laterFetched = nil
            rain = nil
            fetched = nil
        }
        plan?.origin = known(found?.origin)
        plan?.destination = known(found?.destination)
        currentPlan = plan

        guard let plan else {
            publish(nil)
            schedule(at: DepartureEngine.nextWake(after: now, events: events, settings: settings, calendar: .current))
            return
        }

        let interval = DepartureEngine.refreshInterval(minutesUntilLeave: output?.minutesUntilLeave ?? 60)
        if let fetched, now.timeIntervalSince(fetched) < interval {
            show(plan: plan, now: now)
            scheduleTick(now: now, events: events)
        } else {
            refreshing?.cancel()
            refreshing = Task { await refresh(plan, events: events) }
        }
    }

    private func known(_ place: TravelPlace?) -> TravelPlace {
        guard let place else { return TravelPlace(name: "") }
        if place.hasCoordinate { return place }
        return places[EventLocation.key(place.name)] ?? place
    }

    private func readEvents(now: Date) -> [TravelEvent] {
        if let demoEvents { return demoEvents }
        guard settings.home != nil else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let agenda = AgendaStore.shared
        guard let from = calendar.date(byAdding: .day, value: -1, to: today),
            let to = calendar.date(byAdding: .day, value: 2, to: today)
        else { return [] }
        let events = agenda.travelEvents(from: from, to: to)
        guard settings.routine else { return events }
        if routinesRead.map({ !calendar.isDate($0, inSameDayAs: now) }) ?? true,
            let start = calendar.date(byAdding: .day, value: -28, to: today)
        {
            routines = RoutineDetector.routines(history: agenda.travelEvents(from: start, to: today), calendar: calendar)
            routinesRead = now
        }
        return RoutineDetector.apply(routines, to: events)
    }

    private func provider(for mode: TravelMode) -> any TravelProvider {
        switch mode {
        case .transit: transit
        case .car: car
        case .bike: bike
        }
    }

    private func refresh(_ found: TripPlan, events: [TravelEvent]) async {
        var plan = found
        guard let origin = await resolved(plan.origin), let destination = await resolved(plan.destination) else {
            // A location Apple Maps can't place: nothing to say about it, rather than a guess.
            guard !Task.isCancelled else { return }
            publish(nil)
            schedule(at: DepartureEngine.nextWake(after: clock(), events: events, settings: settings, calendar: .current))
            return
        }
        plan.origin = origin
        plan.destination = destination
        currentPlan = plan
        let now = clock()
        let provider = provider(for: plan.mode)
        let departAt = plan.earliestLeave.map { max($0, now) }

        do {
            options = try await provider.options(from: origin, to: destination, departAt: departAt, arriveBy: plan.arriveBy)
            fetched = now
        } catch {
            // Offline or no answer: keep what we know, and try again in a while.
            NSLog("wisp: no travel times: \(error)")
            fetched = now
        }
        guard !Task.isCancelled else { return }

        if plan.mode == .car, settings.nowOrLater,
            laterFetched.map({ now.timeIntervalSince($0) > Self.laterMaxAge }) ?? true
        {
            later = await fetchLater(plan: plan, now: now)
            laterFetched = now
        }
        if plan.mode == .bike, settings.rainCheck {
            rain = (try? await rainProvider.forecast(at: origin, now: now)) ?? rain
        }
        guard !Task.isCancelled else { return }
        show(plan: plan, now: clock())
        scheduleTick(now: clock(), events: events)
    }

    private func resolved(_ place: TravelPlace) async -> TravelPlace? {
        if place.hasCoordinate { return place }
        let key = EventLocation.key(place.name)
        if let known = places[key] { return known }
        guard let found = try? await lookup.place(for: place.name), found.hasCoordinate else { return nil }
        places[key] = found
        return found
    }

    private func fetchLater(plan: TripPlan, now: Date) async -> LaterAdvice? {
        var minutes: [Int: Int] = [:]
        let base = plan.earliestLeave.map { max($0, now) } ?? now
        for offset in [0, 30, 60] {
            let leaving = base.addingTimeInterval(Double(offset) * 60)
            if let option = try? await car.options(from: plan.origin, to: plan.destination, departAt: leaving, arriveBy: nil).first {
                minutes[offset] = option.minutes
            }
        }
        return DepartureEngine.laterAdvice(minutes: minutes, plan: plan, now: base)
    }

    private func show(plan: TripPlan, now: Date) {
        let result = DepartureEngine.resolve(plan: plan, options: options, later: later, rainForecast: rain, now: now)
        // Off in Settings or too far ahead: known, not shown.
        publish(result.isVisible && result.chosen != nil ? result : nil)
    }

    private func publish(_ new: DepartureOutput?) {
        if output != new { output = new }
    }

    // MARK: - Timing

    /// During a trip: on the next minute, for the countdown; only then the calendar is read again.
    private func scheduleTick(now: Date, events: [TravelEvent]) {
        let seconds = 60 - Calendar.current.component(.second, from: now)
        schedule(at: now.addingTimeInterval(Double(max(seconds, 5))))
    }

    private func schedule(at date: Date?) {
        wake?.cancel()
        wake = nil
        guard let date, !asleep else { return }
        let work = DispatchWorkItem { [weak self] in self?.evaluate() }
        wake = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(1, date.timeIntervalSince(clock())), execute: work)
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        let sleep: @Sendable (Notification) -> Void = { _ in
            MainActor.assumeIsolated { DepartureStore.shared.setAsleep(true) }
        }
        let wake: @Sendable (Notification) -> Void = { _ in
            MainActor.assumeIsolated { DepartureStore.shared.setAsleep(false) }
        }
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: sleep))
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: wake))
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main, using: sleep))
        observers.append(distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main, using: wake))
        observers.append(
            NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { DepartureStore.shared.evaluate() }
            })
    }

    private func setAsleep(_ on: Bool) {
        guard asleep != on else { return }
        asleep = on
        if on {
            wake?.cancel()
            wake = nil
            refreshing?.cancel()
        } else {
            fetched = nil
            evaluate()
        }
    }

    #if DEBUG
        private func startDemo(_ mode: String) {
            isDemo = true
            hasNSKey = true
            let now = Date.now
            @Sendable func minutes(_ n: Double) -> Date { now.addingTimeInterval(n * 60) }
            settings.home = TravelPlace(name: "Thuis", latitude: 51.84, longitude: 5.85)
            settings.nowOrLater = true
            settings.rainCheck = true
            var event = TravelEvent(
                id: "demo", title: "Wiskunde", start: minutes(-40), end: minutes(10), location: "School", latitude: 51.9, longitude: 5.9)
            event.isRecurring = true
            demoEvents = [event]
            let chosen = TravelMode(rawValue: mode) ?? .transit
            settings.defaultMode = chosen
            lookup = MockPlaceLookup()
            @Sendable func train(_ leave: Double, _ line: String, delay: Int = 0, cancelled: Bool = false) -> TravelOption {
                TravelOption(
                    departure: minutes(leave), arrival: minutes(leave + 39),
                    legs: [
                        TravelLeg(kind: .walk, departure: minutes(leave), minutes: 6),
                        TravelLeg(
                            kind: .rail, line: "NS", platform: "3", departure: minutes(leave + 6), minutes: 16, delayMinutes: delay,
                            isCancelled: cancelled),
                        TravelLeg(kind: .bus, line: line, platform: "B", departure: minutes(leave + 22), minutes: 17),
                    ], delayMinutes: delay, isCancelled: cancelled)
            }
            transit = MockTravelProvider { _, _ in [train(14, "300"), train(29, "33", delay: 4), train(44, "300", cancelled: true)] }
            car = MockTravelProvider { departAt, _ in
                let leave = departAt ?? minutes(10)
                // The jam thins out over the coming hour.
                let later = leave.timeIntervalSince(now) / 60
                let trip = later > 55 ? 42 : later > 25 ? 50 : 57
                return [
                    TravelOption(
                        departure: leave, arrival: leave.addingTimeInterval(Double(trip) * 60),
                        legs: [TravelLeg(kind: .drive, minutes: trip)], normalMinutes: 42, routeName: "A15")
                ]
            }
            bike = MockTravelProvider { departAt, _ in
                let leave = departAt ?? minutes(10)
                return [
                    TravelOption(departure: leave, arrival: leave.addingTimeInterval(22 * 60), legs: [TravelLeg(kind: .bike, minutes: 22)])
                ]
            }
            let points = (0..<24).map {
                RainForecast.Point(time: minutes(Double($0) * 5), millimetresPerHour: (3...7).contains($0) ? 1.2 : 0)
            }
            rainProvider = MockRainProvider(answer: RainForecast(points: points))
            evaluate()
        }
    #endif
}

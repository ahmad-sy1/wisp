import AppKit
import EventKit
import SwiftUI

/// One event on today's timeline.
struct AgendaEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    /// The calendar's own colour; shifts are drawn in `Theme.warning` instead.
    let color: Color
    let isShift: Bool

    func isPast(at now: Date) -> Bool { !isAllDay && end <= now && start < now }
    func isOngoing(at now: Date) -> Bool { !isAllDay && start <= now && now < end }
}

/// Today's events from the macOS Calendar app (EventKit), for the Agenda tab.
///
/// Reads only while the tab is visible: `setVisible(true)` fetches and starts
/// listening for calendar changes, `setVisible(false)` stops. Nothing is written.
@MainActor
final class AgendaStore: ObservableObject {
    static let shared = AgendaStore()

    enum Access { case notAsked, granted, denied }

    /// How a shift is recognised: by the word "dienst" in the title, or by its calendar.
    enum ShiftRule: Hashable {
        case titleWord
        case calendar(String)
    }

    @Published private(set) var access: Access
    @Published private(set) var events: [AgendaEvent] = []
    /// Tomorrow's events, shown once nothing is left today.
    @Published private(set) var tomorrow: [AgendaEvent] = []
    @Published private(set) var calendars: [EKCalendar] = []

    /// Calendars the user switched off in Settings (by identifier); all others count.
    @Published var hiddenCalendars: Set<String> {
        didSet {
            defaults.set(Array(hiddenCalendars), forKey: Key.hidden)
            reload()
        }
    }

    @Published var shiftRule: ShiftRule {
        didSet {
            switch shiftRule {
            case .titleWord: defaults.removeObject(forKey: Key.shiftCalendar)
            case .calendar(let id): defaults.set(id, forKey: Key.shiftCalendar)
            }
            reload()
        }
    }

    /// Minutes by bike to work, for "Vertrek voor je dienst".
    @Published var travelMinutes: Int {
        didSet { defaults.set(travelMinutes, forKey: Key.travel) }
    }

    static let shiftWord = "dienst"

    private let store = EKEventStore()
    private let defaults = UserDefaults.standard
    private var visible = false
    private var observer: NSObjectProtocol?

    private enum Key {
        static let hidden = "agendaHiddenCalendars"
        static let shiftCalendar = "agendaShiftCalendar"
        static let travel = "agendaTravelMinutes"
    }

    private init() {
        hiddenCalendars = Set(defaults.stringArray(forKey: Key.hidden) ?? [])
        shiftRule = defaults.string(forKey: Key.shiftCalendar).map { .calendar($0) } ?? .titleWord
        travelMinutes = defaults.object(forKey: Key.travel) as? Int ?? 20
        access = Self.currentAccess()
    }

    /// The Agenda tab appeared (`true`) or went away.
    func setVisible(_ on: Bool) {
        visible = on
        if on {
            access = Self.currentAccess()
            startObserving()
            reload()
        } else {
            stopObserving()
        }
    }

    /// Asks macOS for Calendar access (once; later the answer comes from System Settings).
    func requestAccess() {
        // EventKit answers on a background queue: @Sendable keeps Swift from treating
        // the closure as main-actor code (which would trap there).
        store.requestFullAccessToEvents { @Sendable _, _ in
            Task { @MainActor in AgendaStore.shared.accessChanged() }
        }
    }

    /// Opens Privacy & Security → Calendars, for when access was refused.
    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The first shift today that hasn't started yet.
    func nextShift(after now: Date) -> AgendaEvent? {
        events.first { $0.isShift && !$0.isAllDay && $0.start > now }
    }

    /// Settings shows the calendars too, also while the tab is closed.
    func loadCalendars() {
        access = Self.currentAccess()
        guard access == .granted else { return }
        calendars = store.calendars(for: .event).sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    private func accessChanged() {
        access = Self.currentAccess()
        if access == .granted {
            // A fresh store sees the calendars that access just unlocked.
            store.reset()
            loadCalendars()
            reload()
        }
    }

    private func reload() {
        guard visible, access == .granted else { return }
        calendars = store.calendars(for: .event).sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        let shown = calendars.filter { !hiddenCalendars.contains($0.calendarIdentifier) }
        guard !shown.isEmpty else {
            events = []
            tomorrow = []
            return
        }
        let day = Calendar.current.startOfDay(for: .now)
        let next = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        let end = Calendar.current.date(byAdding: .day, value: 1, to: next) ?? next
        // One query for today and tomorrow; an event belongs to the day it starts on.
        let predicate = store.predicateForEvents(withStart: day, end: end, calendars: shown)
        let all = store.events(matching: predicate)
            .map(makeEvent)
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
        events = all.filter { $0.start < next }
        tomorrow = all.filter { $0.start >= next }
    }

    private func makeEvent(_ event: EKEvent) -> AgendaEvent {
        let raw = event.title ?? ""
        let title = raw.isEmpty ? "Zonder titel" : raw
        let isShift: Bool
        switch shiftRule {
        case .titleWord: isShift = title.localizedCaseInsensitiveContains(Self.shiftWord)
        case .calendar(let id): isShift = event.calendar?.calendarIdentifier == id
        }
        return AgendaEvent(
            // A repeating event shares its identifier across days; the start keeps it unique.
            id: "\(event.eventIdentifier ?? UUID().uuidString)@\(event.startDate.timeIntervalSince1970)",
            title: title,
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            color: event.calendar.map { Color(nsColor: $0.color) } ?? Theme.textSecondary,
            isShift: isShift
        )
    }

    private func startObserving() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { _ in
            MainActor.assumeIsolated { AgendaStore.shared.reload() }
        }
    }

    private func stopObserving() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
    }
}

extension Date {
    /// "08:30": always 24-hour, whatever the system's clock setting.
    var clockTime: String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: self)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

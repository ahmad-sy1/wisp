import Foundation

/// What the location field of an event means.
enum EventLocation {
    private static let online = [
        "zoom", "teams", "google meet", "meet.google", "webex", "skype", "facetime",
        "discord", "online", "microsoft teams", "whereby", "slack",
    ]

    /// A place you can travel to: not empty, not a link, not a video call.
    static func isPhysical(_ text: String?) -> Bool {
        guard let text else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !trimmed.contains("://"), !trimmed.hasPrefix("www.") else { return false }
        return !online.contains {
            trimmed == $0 || trimmed.hasPrefix($0 + " ") || trimmed.hasPrefix($0 + ":") || trimmed.hasSuffix(" " + $0)
        }
    }

    /// The same place written the same way, to compare and to remember choices by.
    static func key(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// Recognises your routine: an event you keep having at the same place counts as a trip, also
/// on the days its location field is empty.
enum RoutineDetector {
    /// From this many different days a title at one place is a routine; a repeating event
    /// counts at once.
    static let minimumDays = 3

    /// Normalised title → the location that goes with it.
    static func routines(history: [TravelEvent], calendar: Calendar) -> [String: String] {
        struct Seen {
            var days: Set<Date> = []
            var recurring = false
            var location = ""
        }
        var seen: [String: Seen] = [:]
        for event in history where !event.isAllDay && EventLocation.isPhysical(event.location) {
            let key = EventLocation.key(event.title)
            guard !key.isEmpty, let location = event.location else { continue }
            let id = key + "|" + EventLocation.key(location)
            var entry = seen[id] ?? Seen(location: location)
            entry.days.insert(calendar.startOfDay(for: event.start))
            entry.recurring = entry.recurring || event.isRecurring
            seen[id] = entry
        }
        var result: [String: (location: String, days: Int)] = [:]
        for (id, entry) in seen where entry.recurring || entry.days.count >= minimumDays {
            let title = String(id.prefix { $0 != "|" })
            // A title seen at two places: the one it is at most often.
            if entry.days.count > (result[title]?.days ?? 0) {
                result[title] = (entry.location, entry.days.count)
            }
        }
        return result.mapValues(\.location)
    }

    /// Fills in the location of events that belong to a routine but have none.
    static func apply(_ routines: [String: String], to events: [TravelEvent]) -> [TravelEvent] {
        events.map { event in
            guard !EventLocation.isPhysical(event.location), event.location?.isEmpty != false,
                let location = routines[EventLocation.key(event.title)]
            else { return event }
            var copy = event
            copy.location = location
            return copy
        }
    }
}

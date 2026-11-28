/// A place in the closed notch's list. The order of the cases is the order of importance, and
/// this is the only place that order lives: a feature only says which place it fills.
///
/// Departure is one place, whatever it shows inside (countdown, delay, traffic, rain).
enum ClosedNotchSlot: Int, CaseIterable, Comparable, Sendable {
    case focus
    case departure
    case ciFailed
    case review
    case comments
    case music
    case ciRunning
    case mail

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Everything that wants to stay on the closed notch right now, most important first.
///
/// A feature fills its place while it is active and empties it when it isn't; the notch shows
/// what comes first. Short-lived things (the mail peek, a tick, a flash) aren't in it.
struct ClosedNotchList<Content: Equatable>: Equatable {
    struct Entry: Equatable {
        let slot: ClosedNotchSlot
        let content: Content
    }

    private var contents: [ClosedNotchSlot: Content] = [:]

    init() {}

    /// Fills `slot`, or empties it with nil. A feature whose tab is switched off stays quiet.
    mutating func set(_ slot: ClosedNotchSlot, _ content: Content?, tabOn: Bool = true) {
        contents[slot] = tabOn ? content : nil
    }

    subscript(slot: ClosedNotchSlot) -> Content? { contents[slot] }

    var entries: [Entry] {
        ClosedNotchSlot.allCases.compactMap { slot in contents[slot].map { Entry(slot: slot, content: $0) } }
    }

    /// What the closed notch shows.
    var top: Entry? { entries.first }

    var isEmpty: Bool { contents.isEmpty }
}

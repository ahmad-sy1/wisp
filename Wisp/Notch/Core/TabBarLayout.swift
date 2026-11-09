/// Up to `capacity` tabs fit in the notch. With more, the last spot becomes *More* and
/// holds the rest (board 10.1.1).
enum TabBarLayout {
    enum BadgeTone { case quiet, loud }

    static let capacity = 8

    /// The saved order with tabs of a later version at the end, and `first` always in front.
    static func order<Tab: Equatable>(saved: [Tab], all: [Tab], first: Tab) -> [Tab] {
        [first] + (saved + all.filter { !saved.contains($0) }).filter { $0 != first }
    }

    /// The tone of the dot on *More*: quiet only when nothing but `quiet` tabs wait in it.
    static func moreBadge<Tab: Equatable>(waiting: [Tab], quiet: [Tab]) -> BadgeTone? {
        if waiting.isEmpty { return nil }
        return waiting.allSatisfy(quiet.contains) ? .quiet : .loud
    }

    static func split<Tab>(_ tabs: [Tab]) -> (front: [Tab], more: [Tab]) {
        guard tabs.count > capacity else { return (tabs, []) }
        return (Array(tabs.prefix(capacity - 1)), Array(tabs.dropFirst(capacity - 1)))
    }
}

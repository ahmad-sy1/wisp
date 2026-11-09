/// Up to `capacity` tabs fit in the notch. With more, the last spot becomes *More* and
/// holds the rest (board 10.1.1).
enum TabBarLayout {
    static let capacity = 8

    static func split<Tab>(_ tabs: [Tab]) -> (front: [Tab], more: [Tab]) {
        guard tabs.count > capacity else { return (tabs, []) }
        return (Array(tabs.prefix(capacity - 1)), Array(tabs.dropFirst(capacity - 1)))
    }
}

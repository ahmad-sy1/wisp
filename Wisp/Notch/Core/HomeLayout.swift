import Foundation

/// What Home can show.
enum HomeItem: String, CaseIterable, Codable, Sendable {
    case inProgress, nextEvent, github, music

    var title: String {
        switch self {
        case .inProgress: String(localized: "In progress")
        case .nextEvent: String(localized: "Next event")
        case .github: "GitHub"
        case .music: String(localized: "Music")
        }
    }

    /// For the small plan in Settings.
    var shortTitle: String {
        switch self {
        case .inProgress: String(localized: "Now")
        case .nextEvent: String(localized: "Next")
        case .github: "GitHub"
        case .music: String(localized: "Music")
        }
    }
}

/// How much room an item has on Home (boards 11.1, 11.2): less room means less information,
/// never smaller text.
enum HomePlace: Sendable {
    case small, medium, large
}

/// One to four things on Home, each once, in order.
struct HomeLayout: Equatable, Codable, Sendable {
    static let standard = HomeLayout(items: [.inProgress, .github, .music])
    static let counts = [4, 3, 2, 1]

    let items: [HomeItem]

    init(items: [HomeItem]) {
        var unique: [HomeItem] = []
        for item in items where !unique.contains(item) { unique.append(item) }
        self.items = unique.isEmpty ? [.inProgress] : Array(unique.prefix(4))
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(items: try container.decode([HomeItem].self, forKey: .items))
    }

    var places: [HomePlace] {
        switch items.count {
        case 1: [.large]
        case 2: [.medium, .medium]
        case 3: [.medium, .small, .small]
        default: [.small, .small, .small, .small]
        }
    }

    /// Keeps what fits, and fills new places with what isn't on Home yet.
    func withCount(_ count: Int) -> HomeLayout {
        let unused = HomeItem.allCases.filter { !items.contains($0) }
        return HomeLayout(items: Array((items + unused).prefix(max(1, count))))
    }

    /// Puts `item` at `index`; if it was elsewhere, the two trade places.
    func replacing(at index: Int, with item: HomeItem) -> HomeLayout {
        guard items.indices.contains(index) else { return self }
        var result = items
        if let other = result.firstIndex(of: item) { result[other] = result[index] }
        result[index] = item
        return HomeLayout(items: result)
    }

    /// What each place is called in the chooser.
    static func placeNames(count: Int) -> [String] {
        switch count {
        case 1: [String(localized: "Full width")]
        case 2: [String(localized: "Left"), String(localized: "Right")]
        case 3: [String(localized: "Big, left"), String(localized: "Top right"), String(localized: "Bottom right")]
        default:
            [
                String(localized: "Top left"), String(localized: "Top right"), String(localized: "Bottom left"),
                String(localized: "Bottom right"),
            ]
        }
    }
}

import Foundation

enum IntegrationID: String, Sendable {
    case gmail, github, ns
}

enum IntegrationCategory: String, CaseIterable, Sendable {
    case productivity, developer, lifestyle, business

    var title: String {
        switch self {
        case .productivity: String(localized: "Productivity")
        case .developer: String(localized: "Developer")
        case .lifestyle: String(localized: "Lifestyle")
        case .business: String(localized: "Business")
        }
    }
}

/// One service in *Add integration* (board 10.3.1). Only services that work are listed.
struct IntegrationInfo: Identifiable, Equatable, Sendable {
    let id: IntegrationID
    let name: String
    /// At most three, in the service's own spelling.
    let letters: String
    let tint: UInt32
    let category: IntegrationCategory
    let summary: String
    let details: String
    /// Who the keys are sent to.
    let vendor: String
    let notchPreview: String
    let connectWith: String
    let setupMinutes: Int
    /// Extra words people search for.
    let keywords: [String]
}

enum IntegrationFilter: Hashable, Sendable {
    case all, added
    case category(IntegrationCategory)
}

struct IntegrationListing: Equatable, Sendable {
    var available: [IntegrationInfo]
    var added: [IntegrationInfo]

    var ordered: [IntegrationInfo] { available + added }
    var isEmpty: Bool { available.isEmpty && added.isEmpty }
}

enum IntegrationCatalog {
    static let all: [IntegrationInfo] = [
        IntegrationInfo(
            id: .ns, name: "NS", letters: "NS", tint: 0xFFC917, category: .lifestyle,
            summary: String(localized: "Train departures and delays"),
            details: String(
                localized:
                    "Feeds the departure assistant: your next train, platform and delays, timed to your next shift or lecture."),
            vendor: "NS",
            notchPreview: String(localized: "Next train 16:42 · platform 3 · on time"),
            connectWith: String(localized: "NS API key"), setupMinutes: 2,
            keywords: ["train", "trein", "spoor", "departure", "vertrek"]),
        IntegrationInfo(
            id: .gmail, name: "Gmail", letters: "G", tint: 0xFF6961, category: .productivity,
            summary: String(localized: "Inbox and new-mail alerts"),
            details: String(localized: "Your inbox, the unread count and new-mail alerts in your notch."),
            vendor: "Google",
            notchPreview: String(localized: "New mail · 2 unread"),
            connectWith: String(localized: "App password"), setupMinutes: 2,
            keywords: ["mail", "email", "e-mail", "inbox", "google"]),
        IntegrationInfo(
            id: .github, name: "GitHub", letters: "GH", tint: 0xFFFFFF, category: .developer,
            summary: String(localized: "Pull requests, checks and reviews"),
            details: String(localized: "Your pull requests, their checks and review requests, with a quiet signal in your notch."),
            vendor: "GitHub",
            notchPreview: String(localized: "CI 3/4 · review requested"),
            connectWith: String(localized: "GitHub CLI or token"), setupMinutes: 1,
            keywords: ["git", "code", "pull request", "pr", "ci", "review"]),
    ]

    /// The chips to offer: everything, what's added, and each category that has a service.
    static func filters(of items: [IntegrationInfo] = all) -> [IntegrationFilter] {
        let categories = IntegrationCategory.allCases.filter { category in
            items.contains { $0.category == category }
        }
        return [.all, .added] + categories.map(IntegrationFilter.category)
    }

    static func count(of items: [IntegrationInfo] = all, added: Set<IntegrationID>, filter: IntegrationFilter) -> Int {
        items.filter { passes($0, added: added, filter: filter) }.count
    }

    static func listing(
        of items: [IntegrationInfo] = all,
        added: Set<IntegrationID>,
        filter: IntegrationFilter,
        query: String
    ) -> IntegrationListing {
        let shown = items.filter { passes($0, added: added, filter: filter) && matches($0, query: query) }
        return IntegrationListing(
            available: shown.filter { !added.contains($0.id) },
            added: shown.filter { added.contains($0.id) })
    }

    /// The service `offset` rows from `current`, stopping at both ends of the list.
    static func neighbour(of current: IntegrationID?, in items: [IntegrationInfo], offset: Int) -> IntegrationID? {
        guard !items.isEmpty else { return nil }
        guard let index = items.firstIndex(where: { $0.id == current }) else { return items[0].id }
        return items[min(max(index + offset, 0), items.count - 1)].id
    }

    private static func passes(_ item: IntegrationInfo, added: Set<IntegrationID>, filter: IntegrationFilter) -> Bool {
        switch filter {
        case .all: true
        case .added: added.contains(item.id)
        case .category(let category): item.category == category
        }
    }

    private static func matches(_ item: IntegrationInfo, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let haystack = [item.name, item.summary, item.details, item.category.title] + item.keywords
        return haystack.contains { $0.localizedStandardContains(query) }
    }
}

import XCTest

final class IntegrationCatalogTests: XCTestCase {
    func testAddedServicesMoveToTheirOwnSection() {
        let listing = IntegrationCatalog.listing(added: [.gmail], filter: .all, query: "")
        XCTAssertEqual(listing.added.map(\.id), [.gmail])
        XCTAssertFalse(listing.available.contains { $0.id == .gmail })
        XCTAssertEqual(listing.ordered.count, IntegrationCatalog.all.count)
    }

    func testFilters() {
        XCTAssertEqual(IntegrationCatalog.listing(added: [], filter: .added, query: "").ordered, [])
        XCTAssertEqual(
            IntegrationCatalog.listing(added: [], filter: .category(.developer), query: "").ordered.map(\.id), [.github])
    }

    func testSearchFindsNamesAndWordsPeopleUse() {
        XCTAssertEqual(IntegrationCatalog.listing(added: [], filter: .all, query: "gmail").ordered.map(\.id), [.gmail])
        XCTAssertEqual(IntegrationCatalog.listing(added: [], filter: .all, query: " TREIN ").ordered.map(\.id), [.ns])
        XCTAssertTrue(IntegrationCatalog.listing(added: [], filter: .all, query: "spotify api").isEmpty)
    }

    func testChipsOnlyOfferCategoriesThatHaveAService() {
        let filters = IntegrationCatalog.filters()
        XCTAssertTrue(filters.contains(.category(.developer)))
        XCTAssertFalse(filters.contains(.category(.business)))
        XCTAssertEqual(IntegrationCatalog.count(added: [.ns], filter: .added), 1)
    }

    func testNeighbourStopsAtBothEnds() {
        let items = IntegrationCatalog.all
        XCTAssertEqual(IntegrationCatalog.neighbour(of: items[0].id, in: items, offset: -1), items[0].id)
        XCTAssertEqual(IntegrationCatalog.neighbour(of: items[0].id, in: items, offset: 1), items[1].id)
        XCTAssertEqual(IntegrationCatalog.neighbour(of: items.last?.id, in: items, offset: 1), items.last?.id)
        XCTAssertEqual(IntegrationCatalog.neighbour(of: nil, in: items, offset: 1), items[0].id)
        XCTAssertNil(IntegrationCatalog.neighbour(of: nil, in: [], offset: 1))
    }
}

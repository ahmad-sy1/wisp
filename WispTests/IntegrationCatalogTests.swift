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

    private func spec(_ id: IntegrationID) throws -> ManageSpec {
        try XCTUnwrap(IntegrationCatalog.manageSpec(for: id))
    }

    func testGitHubHasItsOwnPageInsteadOfTheManageWindow() {
        XCTAssertNil(IntegrationCatalog.manageSpec(for: .github))
    }

    func testGmailNeedsAnAddressAndAWholeAppPassword() throws {
        let gmail = try spec(.gmail)
        let password = "abcd efgh ijkl mnop"
        XCTAssertTrue(gmail.canConnect(["address": "a@gmail.com", "password": password]))
        XCTAssertFalse(gmail.canConnect(["address": "a@gmail.com", "password": "short"]))
        XCTAssertFalse(gmail.canConnect(["address": "nope", "password": password]))
        XCTAssertFalse(gmail.canConnect(["address": "@gmail.com", "password": password]))
        XCTAssertFalse(gmail.canConnect([:]))
    }

    func testNSNeedsAKey() throws {
        let ns = try spec(.ns)
        XCTAssertTrue(ns.canConnect(["key": " abc "]))
        XCTAssertFalse(ns.canConnect(["key": "  "]))
    }

    private struct Status: HTTPTransport {
        let code: Int
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            XCTAssertEqual(request.headers["Ocp-Apim-Subscription-Key"], "k")
            return HTTPResponse(status: code, headers: [:], body: Data())
        }
    }

    private struct Offline: HTTPTransport {
        func send(_ request: HTTPRequest) async throws -> HTTPResponse { throw URLError(.notConnectedToInternet) }
    }

    func testNSKeyCheck() async {
        let accepted = await NSTravelProvider(key: "k", transport: Status(code: 200)).checkKey()
        XCTAssertEqual(accepted, .accepted)
        let rejected = await NSTravelProvider(key: "k", transport: Status(code: 401)).checkKey()
        XCTAssertEqual(rejected, .rejected)
        let forbidden = await NSTravelProvider(key: "k", transport: Status(code: 403)).checkKey()
        XCTAssertEqual(forbidden, .rejected)
        // Past the gateway, so the key itself was fine.
        let limited = await NSTravelProvider(key: "k", transport: Status(code: 429)).checkKey()
        XCTAssertEqual(limited, .accepted)
        let refusedRoute = await NSTravelProvider(key: "k", transport: Status(code: 400)).checkKey()
        XCTAssertEqual(refusedRoute, .accepted)
        // Says nothing about the key.
        let serverError = await NSTravelProvider(key: "k", transport: Status(code: 503)).checkKey()
        XCTAssertEqual(serverError, .unreachable)
        let offline = await NSTravelProvider(key: "k", transport: Offline()).checkKey()
        XCTAssertEqual(offline, .unreachable)
    }

    func testStatusFollowsTheWindowFirstThenTheAccount() throws {
        let ns = try spec(.ns)
        let failed = ManagePhase.failed(message: "no", field: "key")
        XCTAssertEqual(ns.status(phase: .idle, account: ManageAccount()), .notConnected)
        XCTAssertEqual(ns.status(phase: .checking, account: ManageAccount()), .checking)
        XCTAssertEqual(ns.status(phase: failed, account: ManageAccount(isConnected: true)), .failed)
        XCTAssertEqual(ns.status(phase: .idle, account: ManageAccount(isConnected: true)), .connected)
        XCTAssertEqual(ns.status(phase: .idle, account: ManageAccount(isConnected: true, health: .connecting)), .checking)
        XCTAssertEqual(ns.status(phase: .idle, account: ManageAccount(isConnected: true, health: .failed("x"))), .failed)
    }

    func testSummary() throws {
        let ns = try spec(.ns)
        XCTAssertEqual(ns.summary(phase: .idle, account: ManageAccount()), ns.blurb)
        XCTAssertEqual(ns.summary(phase: .checking, account: ManageAccount(isConnected: true)), ns.checking)
        XCTAssertEqual(ns.summary(phase: .idle, account: ManageAccount(isConnected: true, summary: "ok")), "ok")
        XCTAssertEqual(ns.summary(phase: .idle, account: ManageAccount(isConnected: true, health: .failed("offline"))), "offline")
    }

    func testAnswerOfTheServiceBecomesAPhase() throws {
        let gmail = try spec(.gmail)
        XCTAssertEqual(gmail.phase(after: .accepted), .idle)
        XCTAssertEqual(gmail.phase(after: .rejected), .failed(message: gmail.rejectedMessage, field: "password"))
        XCTAssertEqual(gmail.phase(after: .unreachable), .failed(message: gmail.unreachableMessage, field: "password"))
    }
}

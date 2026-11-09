import XCTest

final class HomeLayoutTests: XCTestCase {
    func testPlacesFollowTheCount() {
        XCTAssertEqual(HomeLayout(items: [.music]).places, [.large])
        XCTAssertEqual(HomeLayout(items: [.music, .github]).places, [.medium, .medium])
        XCTAssertEqual(HomeLayout.standard.places, [.medium, .small, .small])
        XCTAssertEqual(HomeLayout(items: HomeItem.allCases).places, [.small, .small, .small, .small])
    }

    func testEachItemOnceAndNeverEmpty() {
        XCTAssertEqual(HomeLayout(items: [.music, .music]).items, [.music])
        XCTAssertEqual(HomeLayout(items: []).items, [.inProgress])
    }

    func testGrowingFillsWithWhatIsLeftAndShrinkingKeepsTheStart() {
        let one = HomeLayout(items: [.music])
        XCTAssertEqual(one.withCount(2).items, [.music, .inProgress])
        XCTAssertEqual(one.withCount(4).items.count, 4)
        XCTAssertEqual(HomeLayout.standard.withCount(1).items, [.inProgress])
    }

    func testReplacingSwapsInsteadOfDoubling() {
        XCTAssertEqual(HomeLayout.standard.replacing(at: 0, with: .music).items, [.music, .github, .inProgress])
        XCTAssertEqual(HomeLayout.standard.replacing(at: 1, with: .nextEvent).items, [.inProgress, .nextEvent, .music])
    }

    func testBadDataCannotBreakTheLayout() throws {
        let json = Data(#"{"items":["music","music"]}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(HomeLayout.self, from: json).items, [.music])
    }

    func testEveryCountNamesAllItsPlaces() {
        for count in HomeLayout.counts {
            XCTAssertEqual(HomeLayout.placeNames(count: count).count, count)
        }
    }

    private func pull(_ number: Int, _ status: CheckStatus) -> PullRequest {
        var pull = PullRequest(
            repository: "a/b", number: number, title: "t", url: URL(string: "https://x")!, isDraft: false, updatedAt: .now)
        pull.checks.status = status
        return pull
    }

    func testMostImportantPull() {
        var snapshot = RadarSnapshot()
        XCTAssertNil(snapshot.mostImportant)
        snapshot.mine = [pull(1, .passed)]
        XCTAssertEqual(snapshot.mostImportant?.number, 1)
        snapshot.reviews = [pull(2, .none)]
        XCTAssertEqual(snapshot.mostImportant?.number, 2)
        snapshot.mine.append(pull(3, .failed))
        XCTAssertEqual(snapshot.mostImportant?.number, 3)
    }
}

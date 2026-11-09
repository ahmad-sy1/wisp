import XCTest

final class TabBarLayoutTests: XCTestCase {
    func testAllFitUpToTheCapacity() {
        let tabs = Array(0..<8)
        XCTAssertEqual(TabBarLayout.split(tabs).front, tabs)
        XCTAssertEqual(TabBarLayout.split(tabs).more, [])
    }

    func testOneTooManyMovesTwoSoMoreTakesTheLastSpot() {
        let split = TabBarLayout.split(Array(0..<9))
        XCTAssertEqual(split.front, Array(0..<7))
        XCTAssertEqual(split.more, [7, 8])
    }

    func testHomeGoesFirstAndNewTabsLast() {
        XCTAssertEqual(
            TabBarLayout.order(saved: ["a", "home", "b"], all: ["home", "a", "b", "new"], first: "home"), ["home", "a", "b", "new"])
        XCTAssertEqual(TabBarLayout.order(saved: [], all: ["home", "a"], first: "home"), ["home", "a"])
    }

    func testNoTabs() {
        XCTAssertEqual(TabBarLayout.split([Int]()).front, [])
    }
}

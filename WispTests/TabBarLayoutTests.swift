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

    func testNoTabs() {
        XCTAssertEqual(TabBarLayout.split([Int]()).front, [])
    }
}

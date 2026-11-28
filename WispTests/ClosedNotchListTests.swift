import XCTest

final class ClosedNotchListTests: XCTestCase {
    private func list(_ slots: [ClosedNotchSlot]) -> ClosedNotchList<String> {
        var list = ClosedNotchList<String>()
        for slot in slots { list.set(slot, "\(slot)") }
        return list
    }

    func testEmptyShowsNothing() {
        let list = ClosedNotchList<String>()
        XCTAssertNil(list.top)
        XCTAssertTrue(list.isEmpty)
        XCTAssertEqual(list.entries, [])
    }

    /// The order the closed notch has always had: focus, an urgent status, music, a calm
    /// status, unread mail; a trip goes before GitHub.
    func testOrderIsFixedWhateverTheOrderOfArrival() {
        let all = ClosedNotchSlot.allCases
        XCTAssertEqual(all, [.focus, .departure, .ciFailed, .review, .comments, .music, .ciRunning, .mail])
        XCTAssertEqual(list(all.reversed()).entries.map(\.slot), all)
        XCTAssertEqual(list([.mail, .music, .ciFailed, .departure]).entries.map(\.slot), [.departure, .ciFailed, .music, .mail])
    }

    func testFocusWinsOverEverything() {
        XCTAssertEqual(list([.mail, .ciRunning, .music, .departure, .focus]).top?.slot, .focus)
    }

    func testATripGoesBeforeAFailedRunAndMusic() {
        let list = list([.music, .ciFailed, .departure])
        XCTAssertEqual(list.top, .init(slot: .departure, content: "departure"))
        XCTAssertEqual(list.entries.count, 3, "nothing falls away: the failed run waits behind the trip")
    }

    func testUrgentGitHubGoesBeforeMusicAndARunningCheckAfter() {
        XCTAssertEqual(list([.music, .review]).top?.slot, .review)
        XCTAssertEqual(list([.music, .comments]).top?.slot, .comments)
        XCTAssertEqual(list([.ciRunning, .music]).top?.slot, .music)
        XCTAssertEqual(list([.mail, .ciRunning]).top?.slot, .ciRunning)
    }

    func testEmptyingASlotShowsTheNext() {
        var list = list([.departure, .ciFailed, .music])
        list.set(.departure, nil)
        XCTAssertEqual(list.top?.slot, .ciFailed)
        list.set(.ciFailed, nil)
        XCTAssertEqual(list.top?.slot, .music)
        list.set(.music, nil)
        XCTAssertNil(list.top)
    }

    func testNewContentReplacesTheOldInTheSamePlace() {
        var list = list([.departure, .music])
        list.set(.departure, "12 min")
        list.set(.departure, "11 min")
        XCTAssertEqual(list.entries.map(\.content), ["11 min", "music"])
        XCTAssertEqual(list[.departure], "11 min")
    }

    func testASwitchedOffTabStaysQuiet() {
        var list = list([.ciFailed])
        list.set(.departure, "trip", tabOn: false)
        XCTAssertEqual(list.top?.slot, .ciFailed)
        list.set(.ciFailed, "ci", tabOn: false)
        XCTAssertNil(list.top)
    }

    func testListsWithTheSameContentAreEqual() {
        XCTAssertEqual(list([.music, .mail]), list([.mail, .music]))
        XCTAssertNotEqual(list([.music]), list([.mail]))
    }
}

import XCTest

final class NotchPagerTests: XCTestCase {
    /// departure 60, ciFailed 40, music 34: wings of their own width.
    private let three: [NotchPager.Page] = [
        .init(slot: .departure, wing: 60), .init(slot: .ciFailed, wing: 40), .init(slot: .music, wing: 34),
    ]

    private func pager(_ pages: [NotchPager.Page]? = nil) -> NotchPager {
        var pager = NotchPager()
        pager.update(pages ?? three)
        return pager
    }

    // MARK: - At rest

    func testShowsTheMostImportantAndNeedsNothing() {
        let pager = pager()
        XCTAssertEqual(pager.visible, .departure)
        XCTAssertEqual(pager.wing, 60)
        XCTAssertTrue(pager.isIdle)
        XCTAssertFalse(pager.needsReturn)
        XCTAssertEqual(pager.drawnPages, [0])
    }

    func testOneAlertCantBeBrowsed() {
        var pager = pager([.init(slot: .music, wing: 34)])
        XCTAssertFalse(pager.canBrowse)
        pager.dragBegan()
        pager.dragChanged(by: 100)
        XCTAssertFalse(pager.isDragging)
        XCTAssertEqual(pager.position, 0)
    }

    // MARK: - Dragging

    func testContentFollowsTheFingersAndWidthGoesAlong() {
        var pager = pager()
        pager.dragBegan()
        pager.dragChanged(by: 25)  // half of (60 + 40) / 2
        XCTAssertEqual(pager.position, 0.5, accuracy: 0.001)
        XCTAssertEqual(pager.wing, 50, accuracy: 0.001, "halfway between 60 and 40")
        XCTAssertEqual(pager.drawnPages, [0, 1])
        XCTAssertEqual(pager.offset(of: 0), -25, accuracy: 0.001)
        XCTAssertEqual(pager.offset(of: 1), 25, accuracy: 0.001)
        XCTAssertFalse(pager.isIdle)
    }

    func testLiftingSettlesOnTheNearest() {
        var pager = pager()
        pager.dragBegan()
        pager.dragChanged(by: 30)  // past halfway to the second
        XCTAssertFalse(pager.dragEnded())
        XCTAssertEqual(pager.visible, .ciFailed)
        XCTAssertEqual(pager.wing, 40)
        XCTAssertTrue(pager.isIdle)

        pager.dragBegan()
        pager.dragChanged(by: 10)  // not halfway to the third: stays
        pager.dragEnded()
        XCTAssertEqual(pager.visible, .ciFailed)
    }

    func testOneDragCanPassSeveralAlerts() {
        var pager = pager()
        pager.dragBegan()
        pager.dragChanged(by: 50 + 37)  // all the way to the third
        XCTAssertEqual(pager.position, 2, accuracy: 0.001)
        pager.dragEnded()
        XCTAssertEqual(pager.visible, .music)
    }

    func testDraggingBackGoesToThePrevious() {
        var pager = pager()
        pager.step(by: 1)
        pager.dragBegan()
        pager.dragChanged(by: -30)
        pager.dragEnded()
        XCTAssertEqual(pager.visible, .departure)
    }

    func testTheEndsStretchALittleAndSpringBack() {
        var pager = pager()
        pager.dragBegan()
        pager.dragChanged(by: -500)
        XCTAssertLessThan(pager.position, 0)
        XCTAssertGreaterThan(pager.offset(of: 0), 0)
        XCTAssertLessThanOrEqual(pager.offset(of: 0), NotchPager.maxStretch)
        XCTAssertEqual(pager.wing, 60, "the stretch doesn't change the width")
        XCTAssertEqual(pager.dotOpacity(0), 1, "nor the dots")
        pager.dragEnded()
        XCTAssertEqual(pager.visible, .departure)
        XCTAssertEqual(pager.offset(of: 0), 0)

        pager.step(by: 2)
        pager.dragBegan()
        pager.dragChanged(by: 500)
        XCTAssertGreaterThan(pager.position, 2)
        XCTAssertLessThanOrEqual(-pager.offset(of: 2), NotchPager.maxStretch)
        XCTAssertEqual(pager.wing, 34)
        pager.dragEnded()
        XCTAssertEqual(pager.visible, .music)
    }

    func testTheWingNeverGetsWiderThanTheAlertsItIsBetween() {
        var pager = pager()
        pager.step(by: 1)
        pager.dragBegan()
        for _ in 0..<40 {
            pager.dragChanged(by: 1)
            XCTAssertLessThanOrEqual(pager.wing, 40)
            XCTAssertGreaterThanOrEqual(pager.wing, 34)
        }
    }

    // MARK: - Steps and returning

    func testAWheelStepsOneAtATimeAndStopsAtTheEnds() {
        var pager = pager()
        pager.step(by: -1)
        XCTAssertEqual(pager.visible, .departure)
        pager.step(by: 1)
        pager.step(by: 1)
        pager.step(by: 1)
        XCTAssertEqual(pager.visible, .music)
    }

    func testReturnsToTheFirstAfterBrowsing() {
        var pager = pager()
        pager.step(by: 2)
        XCTAssertTrue(pager.needsReturn)
        pager.returnToFirst()
        XCTAssertEqual(pager.visible, .departure)
        XCTAssertFalse(pager.needsReturn)
        XCTAssertTrue(pager.isIdle, "back at rest: no timer or animation left")
    }

    func testDoesntReturnInTheMiddleOfADrag() {
        var pager = pager()
        pager.step(by: 1)
        pager.dragBegan()
        pager.returnToFirst()
        XCTAssertEqual(pager.visible, .ciFailed)
    }

    // MARK: - The list changes

    func testKeepsShowingTheSameAlertWhenOthersComeAndGo() {
        var pager = pager()
        pager.step(by: 2)  // music
        pager.update([.init(slot: .ciFailed, wing: 40), .init(slot: .music, wing: 34), .init(slot: .mail, wing: 34)])
        XCTAssertEqual(pager.visible, .music)
    }

    func testWhenTheVisibleAlertGoesTheNextTakesItsPlace() {
        var pager = pager()
        pager.step(by: 1)  // ciFailed
        pager.update([.init(slot: .departure, wing: 60), .init(slot: .music, wing: 34)])
        XCTAssertEqual(pager.visible, .music)

        pager.update([.init(slot: .departure, wing: 60)])
        XCTAssertEqual(pager.visible, .departure, "the last one went: the one before")
        pager.update([])
        XCTAssertNil(pager.visible)
    }

    func testTheVisibleAlertGoingEndsADrag() {
        var pager = pager()
        pager.step(by: 1)
        pager.dragBegan()
        pager.dragChanged(by: 10)
        pager.update([.init(slot: .departure, wing: 60), .init(slot: .music, wing: 34)])
        XCTAssertTrue(pager.isIdle)
        XCTAssertEqual(pager.visible, .music)
    }

    func testAnUrgentArrivalWhileBrowsingJumpsToIt() {
        var pager = pager()
        pager.step(by: 2)  // music
        let jumped = pager.update(three + [.init(slot: .review, wing: 50)].sortedLike())
        XCTAssertTrue(jumped)
        XCTAssertEqual(pager.visible, .review)
    }

    func testAnUrgentArrivalDuringADragWaitsForTheFingers() {
        var pager = pager()
        pager.dragBegan()
        pager.dragChanged(by: 10)
        XCTAssertFalse(pager.update((three + [.init(slot: .comments, wing: 30)]).sortedLike()))
        XCTAssertEqual(pager.pendingJump, .comments)
        XCTAssertTrue(pager.dragEnded(), "lifting the fingers jumps")
        XCTAssertEqual(pager.visible, .comments)
    }

    func testTheMostImportantArrivalWins() {
        var pager = pager()
        pager.dragBegan()
        pager.update((three + [.init(slot: .comments, wing: 30)]).sortedLike())
        pager.update((three + [.init(slot: .comments, wing: 30), .init(slot: .review, wing: 50)]).sortedLike())
        pager.dragEnded()
        XCTAssertEqual(pager.visible, .review)
    }

    func testCalmArrivalsAndUpdatesDontJump() {
        var pager = pager()
        pager.step(by: 1)
        XCTAssertFalse(pager.update((three + [.init(slot: .mail, wing: 34)]).sortedLike()))
        XCTAssertFalse(pager.update([.init(slot: .departure, wing: 66)] + three.dropFirst() + [.init(slot: .mail, wing: 34)]))
        XCTAssertEqual(pager.visible, .ciFailed)
    }

    func testNotBrowsingTheMostImportantSimplyShows() {
        var pager = pager()
        XCTAssertFalse(pager.update((three + [.init(slot: .review, wing: 50)]).sortedLike()))
        XCTAssertEqual(pager.visible, .departure)
        XCTAssertFalse(pager.update(([.init(slot: .focus, wing: 34)] + three)))
        XCTAssertEqual(pager.visible, .focus)
    }

    // MARK: - Quiet

    func testQuietEndsBrowsingAndIgnoresSwipes() {
        var pager = pager()
        pager.step(by: 2)
        pager.dragBegan()
        pager.setQuiet(true)
        XCTAssertEqual(pager.visible, .departure)
        XCTAssertTrue(pager.isIdle)
        XCTAssertFalse(pager.canBrowse)
        pager.dragBegan()
        pager.dragChanged(by: 40)
        pager.step(by: 1)
        XCTAssertEqual(pager.visible, .departure)
        XCTAssertFalse(pager.update((three + [.init(slot: .review, wing: 50)]).sortedLike()), "no jumps either")
        pager.setQuiet(false)
        pager.step(by: 1)
        XCTAssertEqual(pager.visible, .ciFailed)
    }

    // MARK: - Dots

    func testDotsFollowTheFingers() {
        var pager = pager()
        XCTAssertEqual(pager.dotOpacity(0), 1)
        XCTAssertEqual(pager.dotOpacity(1), NotchPager.inactiveDot)
        XCTAssertEqual(pager.dotOpacity(2), NotchPager.inactiveDot)
        pager.dragBegan()
        pager.dragChanged(by: 25)
        XCTAssertEqual(pager.dotOpacity(0), 0.66, accuracy: 0.001)
        XCTAssertEqual(pager.dotOpacity(1), 0.66, accuracy: 0.001)
        pager.dragEnded()
        XCTAssertEqual(pager.dotOpacity(1), 1)
        XCTAssertEqual(pager.dotOpacity(0), NotchPager.inactiveDot)
    }
}

extension Array where Element == NotchPager.Page {
    /// In the list's own order, as `ClosedNotchList` hands them over.
    fileprivate func sortedLike() -> [NotchPager.Page] { sorted { $0.slot < $1.slot } }
}

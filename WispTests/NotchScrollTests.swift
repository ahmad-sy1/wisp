import XCTest

final class NotchScrollTests: XCTestCase {
    private func trackpad(_ phase: NotchScrollEvent.Phase, dx: CGFloat = 0, dy: CGFloat = 0) -> NotchScrollEvent {
        NotchScrollEvent(dx: dx, dy: dy, precise: true, phase: phase)
    }

    private func wheel(dy: CGFloat, dx: CGFloat = 0, at time: TimeInterval, inverted: Bool = false, precise: Bool = false)
        -> NotchScrollEvent
    {
        NotchScrollEvent(dx: dx, dy: dy, precise: precise, inverted: inverted, time: time)
    }

    func testAHorizontalSwipeDragsAndEnds() {
        var reader = NotchScrollReader()
        XCTAssertEqual(reader.read(trackpad(.began, dx: -3, dy: 1)), .dragBegan)
        XCTAssertEqual(reader.read(trackpad(.changed, dx: -10)), .drag(10), "fingers left: on to the next")
        XCTAssertEqual(reader.read(trackpad(.changed, dx: 4, dy: 9)), .drag(-4), "once horizontal, it stays horizontal")
        XCTAssertEqual(reader.read(trackpad(.ended)), .dragEnded)
    }

    func testTheAxisIsDecidedByTheFirstMovement() {
        var reader = NotchScrollReader()
        XCTAssertEqual(reader.read(trackpad(.began)), .none)
        XCTAssertEqual(reader.read(trackpad(.changed, dx: -6, dy: 2)), .dragBegan)
        XCTAssertEqual(reader.read(trackpad(.changed, dx: -6)), .drag(6))
    }

    func testAVerticalSwipeIsLeftAlone() {
        var reader = NotchScrollReader()
        XCTAssertEqual(reader.read(trackpad(.began, dx: 1, dy: -8)), .none)
        XCTAssertEqual(reader.read(trackpad(.changed, dx: -20)), .none)
        XCTAssertEqual(reader.read(trackpad(.ended)), .none)
    }

    func testTheGlideAfterwardsIsIgnored() {
        var reader = NotchScrollReader()
        _ = reader.read(trackpad(.began, dx: -5))
        _ = reader.read(trackpad(.ended))
        var glide = trackpad(.none, dx: -30)
        glide.momentum = true
        XCTAssertEqual(reader.read(glide), .none)
    }

    func testOneWheelClickIsOneStepDownIsNext() {
        var reader = NotchScrollReader()
        XCTAssertEqual(reader.read(wheel(dy: -1, at: 0)), .step(1))
        XCTAssertEqual(reader.read(wheel(dy: 1, at: 1)), .step(-1))
    }

    func testNaturalScrollingDoesntTurnTheWheelAround() {
        var reader = NotchScrollReader()
        XCTAssertEqual(reader.read(wheel(dy: 1, at: 0, inverted: true)), .step(1), "still down = next")
    }

    func testAFastSpinRestsBetweenSteps() {
        var reader = NotchScrollReader()
        XCTAssertEqual(reader.read(wheel(dy: -1, at: 0)), .step(1))
        XCTAssertEqual(reader.read(wheel(dy: -1, at: 0.05)), .none)
        XCTAssertEqual(reader.read(wheel(dy: -1, at: 0.1)), .none)
        XCTAssertEqual(reader.read(wheel(dy: -1, at: 0.3)), .step(1))
    }

    func testASmoothWheelAddsUpSmallDeltas() {
        var reader = NotchScrollReader()
        XCTAssertEqual(reader.read(wheel(dy: -5, at: 0, precise: true)), .none)
        XCTAssertEqual(reader.read(wheel(dy: -5, at: 0.01, precise: true)), .none)
        XCTAssertEqual(reader.read(wheel(dy: -5, at: 0.02, precise: true)), .step(1))
    }

    func testATiltWheelGoesSideways() {
        var reader = NotchScrollReader()
        XCTAssertEqual(reader.read(wheel(dy: 0, dx: -1, at: 0)), .step(1))
    }
}

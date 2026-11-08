import XCTest

final class WingTextTests: XCTestCase {
    func testEveryDigitIsEquallyWide() {
        let widths = Set((0...9).map { WingText.width("\($0) min") })
        XCTAssertEqual(widths.count, 1)
    }

    func testChangingProgressKeepsItsWidth() {
        XCTAssertEqual(WingText.width("1/4"), WingText.width("3/8"))
        XCTAssertEqual(WingText.width("#11"), WingText.width("#80"))
    }
}

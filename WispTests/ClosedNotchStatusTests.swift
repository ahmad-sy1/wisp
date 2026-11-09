import XCTest

final class ClosedNotchStatusTests: XCTestCase {
    private func pick(trip: String? = "trip", tripOn: Bool = true, github: String? = "ci", githubOn: Bool = true) -> String? {
        ClosedNotchStatus.pick(trip: trip, tripTabOn: tripOn, github: github, githubTabOn: githubOn)
    }

    func testATripGoesBeforeGitHub() {
        XCTAssertEqual(pick(), "trip")
    }

    func testGitHubShowsWithoutATrip() {
        XCTAssertEqual(pick(trip: nil), "ci")
    }

    func testASwitchedOffDepartureTabStaysQuiet() {
        XCTAssertEqual(pick(tripOn: false), "ci")
        XCTAssertNil(pick(tripOn: false, github: nil))
    }

    func testASwitchedOffGitHubTabStaysQuiet() {
        XCTAssertNil(pick(trip: nil, githubOn: false))
        XCTAssertEqual(pick(githubOn: false), "trip")
        XCTAssertNil(pick(tripOn: false, githubOn: false))
    }
}

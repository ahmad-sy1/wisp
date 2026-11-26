import XCTest

/// Hand-written after the documented v2 shapes, trimmed to the fields wisp reads.
private let recoveryPage = """
    {"records":[
     {"cycle_id":3,"score_state":"SCORED","score":{"recovery_score":67.6,"resting_heart_rate":54,"hrv_rmssd_milli":61.8}},
     {"cycle_id":2,"score_state":"PENDING_SCORE"},
     {"cycle_id":1,"score_state":"SCORED","score":{"recovery_score":31,"resting_heart_rate":60,"hrv_rmssd_milli":40}}
    ],"next_token":null}
    """

private let sleepPage = """
    {"records":[
     {"nap":true,"score_state":"SCORED","score":{"stage_summary":{"total_awake_time_milli":0,
      "total_light_sleep_time_milli":1200000,"total_slow_wave_sleep_time_milli":0,"total_rem_sleep_time_milli":0}}},
     {"nap":false,"score_state":"SCORED","score":{"sleep_performance_percentage":91,"stage_summary":{
      "total_awake_time_milli":1800000,"total_light_sleep_time_milli":13320000,
      "total_slow_wave_sleep_time_milli":6480000,"total_rem_sleep_time_milli":6120000}}}
    ]}
    """

private let cyclePage = """
    {"records":[{"score_state":"SCORED","score":{"strain":9.4321,"kilojoule":7700}}]}
    """

final class WhoopParserTests: XCTestCase {
    func testRecoverySkipsUnscoredDaysAndKeepsHistoryOldestFirst() throws {
        let recovery = try XCTUnwrap(WhoopParser.recovery(Data(recoveryPage.utf8)))
        XCTAssertEqual(recovery.score, 68)
        XCTAssertEqual(recovery.hrv, 62)
        XCTAssertEqual(recovery.restingHeartRate, 54)
        XCTAssertEqual(recovery.recent, [31, 68])
    }

    func testSleepIgnoresNaps() throws {
        let sleep = try XCTUnwrap(WhoopParser.sleep(Data(sleepPage.utf8)))
        XCTAssertEqual(WhoopFormat.duration(sleep.asleep), "7h 12m")
        XCTAssertEqual(sleep.awake, 1800)
        XCTAssertEqual(sleep.performance, 91)
    }

    func testStrainRoundsToOneDecimal() throws {
        let strain = try XCTUnwrap(WhoopParser.strain(Data(cyclePage.utf8)))
        XCTAssertEqual(strain.score, 9.4)
        XCTAssertEqual(strain.kilocalories, 1840)
    }

    func testNothingScoredYet() throws {
        XCTAssertNil(try WhoopParser.recovery(Data(#"{"records":[]}"#.utf8)))
        XCTAssertNil(try WhoopParser.strain(Data(#"{"records":[{"score_state":"UNSCORABLE"}]}"#.utf8)))
    }

    func testZones() {
        XCTAssertEqual(RecoveryZone(68), .green)
        XCTAssertEqual(RecoveryZone(66), .yellow)
        XCTAssertEqual(RecoveryZone(33), .red)
    }
}

final class WhoopOAuthTests: XCTestCase {
    private let client = WhoopOAuth.Client(id: "abc", secret: "s&cret")

    func testAuthorizationURLAsksForOfflineAccess() throws {
        let url = WhoopOAuth.authorizationURL(client: client, state: "12345678")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "client_id" }?.value, "abc")
        XCTAssertEqual(items.first { $0.name == "redirect_uri" }?.value, "wisp://oauth/whoop")
        XCTAssertTrue(items.first { $0.name == "scope" }?.value?.contains("offline") == true)
        XCTAssertEqual(WhoopOAuth.makeState().count, 8)
    }

    func testCallbackNeedsTheSameState() {
        let good = URL(string: "wisp://oauth/whoop?code=xyz&state=12345678")!
        XCTAssertEqual(WhoopOAuth.parseCallback(good, state: "12345678"), .code("xyz"))
        XCTAssertNil(WhoopOAuth.parseCallback(good, state: "87654321"))
        XCTAssertNil(WhoopOAuth.parseCallback(URL(string: "wisp://oauth/other?code=xyz&state=12345678")!, state: "12345678"))
        let denied = URL(string: "wisp://oauth/whoop?error=access_denied&state=12345678")!
        XCTAssertEqual(WhoopOAuth.parseCallback(denied, state: "12345678"), .denied("access_denied"))
    }

    func testTokenRequestsEncodeTheSecret() throws {
        let request = WhoopOAuth.refreshRequest("r1", client: client)
        let body = try XCTUnwrap(request.body.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertEqual(request.method, "POST")
        XCTAssertTrue(body.contains("client_secret=s%26cret"))
        XCTAssertTrue(body.contains("grant_type=refresh_token"))
        XCTAssertTrue(body.contains("scope=offline"))
    }
}

final class WhoopClientTests: XCTestCase {
    private let client = WhoopOAuth.Client(id: "abc", secret: "def")
    private let now = Date(timeIntervalSince1970: 1_000_000)

    /// Answers by path; counts token refreshes.
    private final class Server: HTTPTransport, @unchecked Sendable {
        var refreshes = 0
        var refreshStatus = 200
        let lock = NSLock()

        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            let path = request.url.absoluteString
            if path.hasSuffix("oauth2/token") {
                lock.withLock { refreshes += 1 }
                let body = #"{"access_token":"new","refresh_token":"r2","expires_in":3600}"#
                return HTTPResponse(status: refreshStatus, headers: [:], body: Data(body.utf8))
            }
            guard request.headers["Authorization"] == "Bearer new" else {
                return HTTPResponse(status: 401, headers: [:], body: Data())
            }
            let body =
                path.contains("recovery") ? recoveryPage : path.contains("sleep") ? sleepPage : cyclePage
            return HTTPResponse(status: 200, headers: [:], body: Data(body.utf8))
        }
    }

    private final class Saved: @unchecked Sendable {
        var tokens: [WhoopOAuth.Tokens] = []
    }

    func testRefreshesOnceForThreeRequestsAndSavesTheNewPair() async throws {
        let server = Server()
        let saved = Saved()
        let expired = WhoopOAuth.Tokens(access: "old", refresh: "r1", expires: now)
        let whoop = WhoopClient(
            transport: server, client: client, tokens: expired, save: { saved.tokens.append($0) }, now: { [now] in now })
        let today = try await whoop.today()
        XCTAssertEqual(today.recovery?.score, 68)
        XCTAssertEqual(today.strain?.score, 9.4)
        XCTAssertEqual(server.refreshes, 1)
        XCTAssertEqual(saved.tokens.map(\.refresh), ["r2"])
    }

    func testRevokingRefreshesWithoutSaving() async {
        let server = Server()
        let saved = Saved()
        let expired = WhoopOAuth.Tokens(access: "old", refresh: "r1", expires: now)
        let whoop = WhoopClient(
            transport: server, client: client, tokens: expired, save: { saved.tokens.append($0) }, now: { [now] in now })
        await whoop.revoke()
        XCTAssertEqual(server.refreshes, 1)
        XCTAssertTrue(saved.tokens.isEmpty, "disconnected tokens must not come back")
    }

    func testRefusedRefreshMeansSignedOut() async {
        let server = Server()
        server.refreshStatus = 400
        let expired = WhoopOAuth.Tokens(access: "old", refresh: "r1", expires: now)
        let whoop = WhoopClient(transport: server, client: client, tokens: expired, save: { _ in }, now: { [now] in now })
        do {
            _ = try await whoop.today()
            XCTFail("expected signedOut")
        } catch {
            XCTAssertEqual(error as? WhoopError, .signedOut)
        }
    }
}

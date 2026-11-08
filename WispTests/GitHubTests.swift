import XCTest

private func pull(
    _ number: Int, sha: String? = "abc", status: CheckStatus = .none, jobs: [FailedJob] = [],
    updated: Date = Date(timeIntervalSince1970: 1000)
) -> PullRequest {
    var pr = PullRequest(
        repository: "me/wisp", number: number, title: "PR \(number)",
        url: URL(string: "https://github.com/me/wisp/pull/\(number)")!, isDraft: false, updatedAt: updated)
    pr.headSHA = sha
    pr.checks = CheckSummary(status: status, completed: 0, total: status == .none ? 0 : 1, failedJobs: jobs)
    return pr
}

private func activity(_ author: String, _ seconds: TimeInterval) -> PullActivity {
    PullActivity(kind: .comment, author: author, date: Date(timeIntervalSince1970: seconds), url: nil)
}

private let baseline: RadarSeen = {
    var seen = RadarSeen()
    seen.hasBaseline = true
    return seen
}()

final class CheckAggregatorTests: XCTestCase {
    private func run(_ name: String, _ status: String, _ conclusion: String? = nil) -> CheckRun {
        CheckRun(name: name, status: status, conclusion: conclusion, url: URL(string: "https://x/\(name)"))
    }

    func testNoChecks() {
        XCTAssertEqual(CheckAggregator.summarize(runs: [], statuses: []).status, .none)
    }

    func testRunningCountsCompleted() {
        let sum = CheckAggregator.summarize(
            runs: [run("a", "completed", "success"), run("b", "in_progress"), run("c", "queued")], statuses: [])
        XCTAssertEqual(sum.status, .running)
        XCTAssertEqual(sum.completed, 1)
        XCTAssertEqual(sum.total, 3)
    }

    func testFailureWinsOverRunning() {
        let sum = CheckAggregator.summarize(runs: [run("build", "completed", "failure"), run("b", "in_progress")], statuses: [])
        XCTAssertEqual(sum.status, .failed)
        XCTAssertEqual(sum.failedJobs.first?.name, "build")
        XCTAssertEqual(sum.url, URL(string: "https://x/build"))
    }

    func testCancelledAndSkippedAreNotFailures() {
        let sum = CheckAggregator.summarize(
            runs: [run("a", "completed", "cancelled"), run("b", "completed", "skipped"), run("c", "completed", "neutral")], statuses: [])
        XCTAssertEqual(sum.status, .passed)
    }

    func testTimedOutIsAFailure() {
        XCTAssertEqual(CheckAggregator.summarize(runs: [run("a", "completed", "timed_out")], statuses: []).status, .failed)
    }

    func testLegacyStatuses() {
        let pending = CommitStatus(context: "ci/old", state: "pending", url: nil)
        XCTAssertEqual(CheckAggregator.summarize(runs: [], statuses: [pending]).status, .running)
        let failed = CommitStatus(context: "ci/old", state: "error", url: nil)
        XCTAssertEqual(
            CheckAggregator.summarize(runs: [run("a", "completed", "success")], statuses: [failed]).failedJobs.first?.name, "ci/old")
    }
}

final class PollScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1000)

    func testRunningIsFastQuietIsSlow() {
        XCTAssertEqual(PollSchedule.nextDelay(PollInput(anyRunning: true), now: now), 25)
        XCTAssertEqual(PollSchedule.nextDelay(PollInput(recentlyActive: true), now: now), 60)
        XCTAssertEqual(PollSchedule.nextDelay(PollInput(), now: now), 180)
    }

    func testFailuresBackOffUpToALimit() {
        XCTAssertEqual(PollSchedule.nextDelay(PollInput(consecutiveFailures: 1), now: now), 60)
        XCTAssertEqual(PollSchedule.nextDelay(PollInput(consecutiveFailures: 3), now: now), 240)
        XCTAssertEqual(PollSchedule.nextDelay(PollInput(consecutiveFailures: 30), now: now), 900)
        // Even with a run going.
        XCTAssertEqual(PollSchedule.nextDelay(PollInput(anyRunning: true, consecutiveFailures: 2), now: now), 120)
    }

    func testRetryAfterWins() {
        let input = PollInput(anyRunning: true, blockedUntil: now.addingTimeInterval(500))
        XCTAssertEqual(PollSchedule.nextDelay(input, now: now), 500)
    }

    func testLowRateLimitWaitsForReset() {
        let reset = now.addingTimeInterval(1200)
        XCTAssertEqual(PollSchedule.nextDelay(PollInput(anyRunning: true, rateRemaining: 20, rateReset: reset), now: now), 1200)
        XCTAssertEqual(PollSchedule.nextDelay(PollInput(anyRunning: true, rateRemaining: 2000, rateReset: reset), now: now), 25)
    }
}

final class RadarDiffTests: XCTestCase {
    private func diff(
        _ mine: [PullRequest] = [], reviews: [PullRequest] = [], activity: [String: [PullActivity]] = [:],
        seen: RadarSeen = baseline
    ) -> ([RadarEvent], RadarSeen) {
        let result = Radar.diff(snapshot: RadarSnapshot(mine: mine, reviews: reviews), activity: activity, login: "me", seen: seen)
        return (result.events, result.seen)
    }

    func testFirstAnswerIsSilent() {
        let (events, seen) = diff(
            [pull(1, status: .failed)], reviews: [pull(2)],
            activity: ["me/wisp#1": [activity("sam", 5)]], seen: RadarSeen())
        XCTAssertEqual(events, [])
        XCTAssertTrue(seen.hasBaseline)
        XCTAssertEqual(seen.unseenActivity, [:])
        XCTAssertEqual(seen.lastActivity["me/wisp#1"], Date(timeIntervalSince1970: 5))
    }

    func testRunningToFailedFiresOnce() {
        let (_, running) = diff([pull(1, status: .running)])
        let job = FailedJob(name: "build", url: nil)
        let failed = pull(1, status: .failed, jobs: [job])
        let (events, seen) = diff([failed], seen: running)
        XCTAssertEqual(events, [.checksFailed(failed, job)])
        XCTAssertEqual(diff([failed], seen: seen).0, [])
    }

    func testRunningToPassedFires() {
        let (_, running) = diff([pull(1, status: .running)])
        let passed = pull(1, status: .passed)
        XCTAssertEqual(diff([passed], seen: running).0, [.checksPassed(passed)])
    }

    func testNewPullRequestGreenIsNotNewsButRedIs() {
        XCTAssertEqual(diff([pull(1, status: .passed)]).0, [])
        let red = pull(2, status: .failed)
        XCTAssertEqual(diff([red]).0, [.checksFailed(red, nil)])
    }

    func testNewCommitThatFailsAgainFiresAgain() {
        let (_, first) = diff([pull(1, sha: "a", status: .failed)])
        let second = pull(1, sha: "b", status: .failed)
        XCTAssertEqual(diff([second], seen: first).0, [.checksFailed(second, nil)])
    }

    func testReviewRequestFiresOnceAndAgainAfterRemoval() {
        let pr = pull(9)
        let (events, seen) = diff(reviews: [pr])
        XCTAssertEqual(events, [.reviewRequested(pr)])
        XCTAssertEqual(diff(reviews: [pr], seen: seen).0, [])
        let (_, gone) = diff(reviews: [], seen: seen)
        XCTAssertEqual(diff(reviews: [pr], seen: gone).0, [.reviewRequested(pr)])
    }

    func testCommentsReportOnceWithAuthorSkippingMineAndBots() {
        let pr = pull(1)
        let items = [activity("sam", 10), activity("me", 11), activity("dependabot[bot]", 12), activity("lou", 13)]
        let (events, seen) = diff([pr], activity: ["me/wisp#1": items])
        XCTAssertEqual(events, [.newActivity(pr, author: "lou", count: 2)])
        XCTAssertEqual(seen.unseenActivity["me/wisp#1"], 2)
        XCTAssertEqual(diff([pr], activity: ["me/wisp#1": items], seen: seen).0, [])
    }

    func testOnlyOwnCommentsAreNotNews() {
        let (events, seen) = diff([pull(1)], activity: ["me/wisp#1": [activity("ME", 10)]])
        XCTAssertEqual(events, [])
        XCTAssertNil(seen.unseenActivity["me/wisp#1"])
    }

    func testClosedPullRequestsAreForgotten() {
        let (_, seen) = diff([pull(1, status: .running)], activity: ["me/wisp#1": [activity("sam", 10)]])
        let (_, after) = diff([], seen: seen)
        XCTAssertEqual(after.checks, [:])
        XCTAssertEqual(after.lastActivity, [:])
        XCTAssertEqual(after.unseenActivity, [:])
    }
}

final class RadarCompactTests: XCTestCase {
    private let all = RadarNotifications()

    func testNothingWrongShowsNothing() {
        XCTAssertEqual(Radar.compact(snapshot: RadarSnapshot(mine: [pull(1, status: .passed)]), seen: baseline, notifications: all), .none)
    }

    func testPriorityFailedThenReviewThenCommentsThenRunning() {
        let failed = pull(1, status: .failed, jobs: [FailedJob(name: "build", url: nil)])
        let running = { () -> PullRequest in
            var p = pull(2, status: .running)
            p.checks.completed = 2
            p.checks.total = 5
            return p
        }()
        let review = pull(3)
        var seen = baseline
        seen.unseenActivity = [running.id: 3]
        var snapshot = RadarSnapshot(mine: [running, failed], reviews: [review])
        XCTAssertEqual(Radar.compact(snapshot: snapshot, seen: seen, notifications: all), .failed(failed, job: "build"))
        snapshot.mine = [running]
        XCTAssertEqual(Radar.compact(snapshot: snapshot, seen: seen, notifications: all), .reviewRequested(review, count: 1))
        snapshot.reviews = []
        XCTAssertEqual(Radar.compact(snapshot: snapshot, seen: seen, notifications: all), .newActivity(running, count: 3))
        seen.unseenActivity = [:]
        XCTAssertEqual(Radar.compact(snapshot: snapshot, seen: seen, notifications: all), .running(completed: 2, total: 5))
    }

    func testAcknowledgingClearsDotsUntilANewCommitFails() {
        let failed = pull(1, sha: "a", status: .failed)
        let snapshot = RadarSnapshot(mine: [failed], reviews: [pull(2)])
        var seen = baseline
        seen.unseenActivity = [failed.id: 1]
        let looked = Radar.acknowledge(snapshot: snapshot, seen: seen)
        XCTAssertEqual(Radar.compact(snapshot: snapshot, seen: looked, notifications: all), .none)
        let again = RadarSnapshot(mine: [pull(1, sha: "b", status: .failed)], reviews: [pull(2)])
        XCTAssertEqual(Radar.compact(snapshot: again, seen: looked, notifications: all), .failed(again.mine[0], job: nil))
    }

    func testSwitchedOffNotificationsDontShow() {
        var off = all
        off.failed = false
        off.review = false
        let snapshot = RadarSnapshot(mine: [pull(1, status: .failed)], reviews: [pull(2)])
        XCTAssertEqual(Radar.compact(snapshot: snapshot, seen: baseline, notifications: off), .none)
    }
}

final class StreakTests: XCTestCase {
    func testStreak() {
        XCTAssertEqual(Radar.streak(days: []), 0)
        XCTAssertEqual(Radar.streak(days: [1, 0, 2, 3]), 2)
        XCTAssertEqual(Radar.streak(days: [1, 2, 0]), 2, "today without contributions doesn't break it")
        XCTAssertEqual(Radar.streak(days: [1, 0, 0]), 0)
    }
}

/// Records requests and answers from a script.
private final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    var answers: [HTTPResponse]
    var requests: [HTTPRequest] = []

    init(_ answers: [HTTPResponse]) { self.answers = answers }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        return answers.removeFirst()
    }
}

final class GitHubClientTests: XCTestCase {
    private func json(_ text: String, status: Int = 200, headers: [String: String] = [:]) -> HTTPResponse {
        HTTPResponse(status: status, headers: headers, body: Data(text.utf8))
    }

    func testConditionalRequestReusesTheBodyOn304() async throws {
        let transport = ScriptedTransport([
            json(#"{"login":"me"}"#, headers: ["etag": "\"v1\""]),
            json("", status: 304),
        ])
        let client = GitHubClient(token: "t", transport: transport)
        let first = try await client.viewerLogin()
        let second = try await client.viewerLogin()
        XCTAssertEqual(first, "me")
        XCTAssertEqual(second, "me")
        XCTAssertNil(transport.requests[0].headers["If-None-Match"])
        XCTAssertEqual(transport.requests[1].headers["If-None-Match"], "\"v1\"")
        XCTAssertEqual(transport.requests[0].headers["Authorization"], "Bearer t")
    }

    func testRateLimitHeadersAreKept() async throws {
        let transport = ScriptedTransport([json(#"{"login":"me"}"#, headers: ["x-ratelimit-remaining": "42", "x-ratelimit-reset": "2000"])])
        let client = GitHubClient(token: "t", transport: transport)
        _ = try await client.viewerLogin()
        let limit = await client.rateLimit()
        XCTAssertEqual(limit.remaining, 42)
        XCTAssertEqual(limit.reset, Date(timeIntervalSince1970: 2000))
    }

    func testErrors() async {
        for (answer, expected) in [
            (json("", status: 401), GitHubError.unauthorized),
            (json("", status: 500), GitHubError.http(500)),
            (
                json("", status: 403, headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "2000"]),
                GitHubError.rateLimited(until: Date(timeIntervalSince1970: 2000))
            ),
            (json("not json"), GitHubError.decoding),
        ] {
            let client = GitHubClient(token: "t", transport: ScriptedTransport([answer]))
            do {
                _ = try await client.viewerLogin()
                XCTFail("expected \(expected)")
            } catch {
                XCTAssertEqual(error as? GitHubError, expected)
            }
        }
    }

    func testRetryAfterMeansBlocked() async {
        let client = GitHubClient(token: "t", transport: ScriptedTransport([json("", status: 403, headers: ["retry-after": "60"])]))
        do {
            _ = try await client.viewerLogin()
            XCTFail("expected a rate limit")
        } catch GitHubError.rateLimited(let until) {
            XCTAssertEqual(until.timeIntervalSinceNow, 60, accuracy: 5)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testSearchParsesRepositoryAndDates() async throws {
        let body = """
            {"items":[{"number":43,"title":"feat: x","html_url":"https://github.com/me/wisp/pull/43",
            "repository_url":"https://api.github.com/repos/me/wisp","updated_at":"2026-11-05T01:28:42Z","draft":false,"user":{"login":"me"}}]}
            """
        let client = GitHubClient(token: "t", transport: ScriptedTransport([json(body)]))
        let pulls = try await client.search("is:pr")
        XCTAssertEqual(pulls.first?.id, "me/wisp#43")
        XCTAssertEqual(pulls.first?.repositoryName, "wisp")
        XCTAssertEqual(pulls.first?.updatedAt, ISO8601DateFormatter().date(from: "2026-11-05T01:28:42Z"))
    }

    func testChecksCombineRunsAndStatuses() async throws {
        let client = GitHubClient(
            token: "t",
            transport: ScriptedTransport([
                json(#"{"check_runs":[{"name":"build","status":"completed","conclusion":"failure","html_url":"https://x/1"}]}"#),
                json(#"{"statuses":[{"context":"old","state":"success","target_url":null}]}"#),
            ]))
        let checks = try await client.checks(repository: "me/wisp", sha: "abc")
        XCTAssertEqual(checks.status, .failed)
        XCTAssertEqual(checks.total, 2)
        XCTAssertEqual(checks.failedJobs.first?.url, URL(string: "https://x/1"))
    }

    func testContributionsParse() throws {
        let body = """
            {"data":{"viewer":{"year":{"contributionCalendar":{"weeks":[{"contributionDays":[
              {"contributionCount":0,"contributionLevel":"NONE"},{"contributionCount":3,"contributionLevel":"SECOND_QUARTILE"},
              {"contributionCount":9,"contributionLevel":"FOURTH_QUARTILE"}]}]}},"week":{"totalCommitContributions":34}},
              "search":{"issueCount":5}}}
            """
        let stats = try GitHubClient.parseContributions(Data(body.utf8))
        XCTAssertEqual(stats, ContributionStats(weeks: [[0, 2, 4]], streak: 2, commitsThisWeek: 34, mergedThisWeek: 5))
    }
}

final class RadarSyncTests: XCTestCase {
    func testOnlyFetchesActivityWhenThePullRequestMoved() async throws {
        let pr = pull(1, sha: "abc")
        let mock = MockGitHubService(mine: [pr], checks: ["abc": CheckSummary(status: .running, completed: 1, total: 2)])
        let sync = RadarSync(service: mock)

        let first = try await sync.refresh(excluded: [], lastActivity: [:])
        XCTAssertEqual(first.snapshot.mine.first?.checks.status, .running)
        XCTAssertTrue(first.snapshot.anyRunning)
        _ = try await sync.refresh(excluded: [], lastActivity: [:])
        var calls = await mock.activityCalls
        XCTAssertEqual(calls, 0, "first look and unchanged updatedAt: no activity requests")
        var checks = await mock.checksCalls
        XCTAssertEqual(checks, 2, "checks don't move updatedAt: asked each round")

        await mock.set(mine: [pull(1, sha: "abc", updated: Date(timeIntervalSince1970: 2000))])
        _ = try await sync.refresh(excluded: [], lastActivity: [:])
        calls = await mock.activityCalls
        checks = await mock.checksCalls
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(checks, 3)
    }

    func testCommentsAfterAPullRequestMovedAreNewerThanTheFirstLook() async throws {
        let first = Date(timeIntervalSince1970: 1000)
        let mock = MockGitHubService(mine: [pull(1, updated: first)])
        await mock.set(activity: ["me/wisp#1": [activity("old", 500), activity("new", 1500)]])
        let sync = RadarSync(service: mock)
        _ = try await sync.refresh(excluded: [], lastActivity: [:])
        await mock.set(mine: [pull(1, updated: Date(timeIntervalSince1970: 2000))])
        let result = try await sync.refresh(excluded: [], lastActivity: [:])
        XCTAssertEqual(result.activity["me/wisp#1"]?.map(\.author), ["new"])
    }

    func testAfterARestartSavedActivityStillCatchesUp() async throws {
        let mock = MockGitHubService(mine: [pull(1)])
        await mock.set(activity: ["me/wisp#1": [activity("old", 500), activity("new", 1500)]])
        let result = try await RadarSync(service: mock).refresh(
            excluded: [], lastActivity: ["me/wisp#1": Date(timeIntervalSince1970: 1000)])
        XCTAssertEqual(result.activity["me/wisp#1"]?.map(\.author), ["new"])
    }

    func testTheListIsReportedBeforeTheChecks() async throws {
        final class Box: @unchecked Sendable { var seen: RadarSnapshot? }
        let box = Box()
        let mock = MockGitHubService(mine: [pull(1)], checks: ["abc": CheckSummary(status: .passed, completed: 1, total: 1)])
        let sync = RadarSync(service: mock)
        let result = try await sync.refresh(excluded: [], lastActivity: [:], found: { box.seen = $0 })
        XCTAssertEqual(box.seen?.mine.count, 1)
        XCTAssertEqual(result.snapshot.mine.first?.checks.status, .passed)
    }

    func testExcludedRepositoriesDontCount() async throws {
        let mock = MockGitHubService(mine: [pull(1)], reviews: [pull(2)])
        let result = try await RadarSync(service: mock).refresh(excluded: ["me/wisp"], lastActivity: [:])
        XCTAssertEqual(result.snapshot, RadarSnapshot())
    }

    func testErrorsPropagateSoTheStoreCanBackOff() async {
        let mock = MockGitHubService()
        await mock.set(failure: .unauthorized)
        do {
            _ = try await RadarSync(service: mock).refresh(excluded: [], lastActivity: [:])
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? GitHubError, .unauthorized)
        }
    }
}

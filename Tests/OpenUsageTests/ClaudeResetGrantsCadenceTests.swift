import XCTest
@testable import OpenUsage

/// The reset-grants request is the one Anthropic throttles when polled, so a regular refresh reads plain
/// usage and the Rate Limit Resets row is checked at most once an hour per account.
@MainActor
final class ClaudeResetGrantsCadenceTests: XCTestCase {
    private nonisolated static let start = OpenUsageISO8601.date(from: "2026-10-09T12:00:00.000Z")!

    func testRegularRefreshReadsPlainUsageAndChecksResetGrantsHourly() async throws {
        let clock = TestClock(Self.start)
        let http = RoutingHTTPClient { request in
            switch request.url.path {
            case "/api/oauth/usage":
                return request.url.query == nil ? Self.usage() : Self.grants(resetsLeft: 1)
            default:
                return HTTPResponse(statusCode: 404, headers: [:], body: Data())
            }
        }
        let runtime = try makeRuntime(http: http, clock: clock)

        let first = await runtime.refresh()
        clock.set(Self.start.addingTimeInterval(5 * 60))
        let second = await runtime.refresh()
        clock.set(Self.start.addingTimeInterval(61 * 60))
        _ = await runtime.refresh()

        XCTAssertEqual(usageQueries(http), [nil, "cedar_ember=1&skip_spend=1", nil, nil, "cedar_ember=1&skip_spend=1"])
        XCTAssertEqual(resetsAvailable(first.lines), 1)
        XCTAssertEqual(resetsAvailable(second.lines), 1)
    }

    func testFailedResetGrantsCheckKeepsBarsAndWaitsAnHour() async throws {
        let clock = TestClock(Self.start)
        let http = RoutingHTTPClient { request in
            switch request.url.path {
            case "/api/oauth/usage":
                return request.url.query == nil
                    ? Self.usage()
                    : HTTPResponse(statusCode: 429, headers: ["retry-after": "3000"], body: Data())
            default:
                return HTTPResponse(statusCode: 404, headers: [:], body: Data())
            }
        }
        let runtime = try makeRuntime(http: http, clock: clock)

        let first = await runtime.refresh()
        clock.set(Self.start.addingTimeInterval(5 * 60))
        let second = await runtime.refresh()

        XCTAssertNil(first.warning)
        XCTAssertNotNil(first.line(label: "Session"))
        XCTAssertNil(resetsAvailable(first.lines))
        XCTAssertNotNil(second.line(label: "Session"))
        XCTAssertEqual(usageQueries(http), [nil, "cedar_ember=1&skip_spend=1", nil])
    }

    func testHeldResetGrantDropsOnceItsDeadlinePasses() async throws {
        let clock = TestClock(Self.start)
        let deadline = Self.start.addingTimeInterval(10 * 60)
        let http = RoutingHTTPClient { request in
            switch request.url.path {
            case "/api/oauth/usage":
                return request.url.query == nil ? Self.usage() : Self.grants(resetsLeft: 1, endsAt: deadline)
            default:
                return HTTPResponse(statusCode: 404, headers: [:], body: Data())
            }
        }
        let runtime = try makeRuntime(http: http, clock: clock)

        let first = await runtime.refresh()
        clock.set(Self.start.addingTimeInterval(15 * 60))
        let second = await runtime.refresh()

        XCTAssertEqual(resetsAvailable(first.lines), 1)
        XCTAssertEqual(resetsAvailable(second.lines), 0)
    }

    func testTokenRotationKeepsLastGoodGrantsWhenHourlyCheckFails() async throws {
        let clock = TestClock(Self.start)
        let http = RoutingHTTPClient { request in
            switch request.url.path {
            case "/v1/oauth/token":
                return HTTPResponse(statusCode: 200, headers: [:], body: Data(
                    #"{"access_token":"token-b","refresh_token":"refresh-b","expires_in":7200}"#.utf8))
            case "/api/oauth/usage":
                if request.url.query == nil { return Self.usage() }
                return request.headers["Authorization"] == "Bearer token-a"
                    ? Self.grants(resetsLeft: 1)
                    : HTTPResponse(statusCode: 429, headers: [:], body: Data())
            default:
                return HTTPResponse(statusCode: 404, headers: [:], body: Data())
            }
        }
        let runtime = try makeRuntime(http: http, clock: clock, expiresAt: Self.start.addingTimeInterval(30 * 60))

        let first = await runtime.refresh()
        clock.set(Self.start.addingTimeInterval(61 * 60))
        let rotated = await runtime.refresh()
        clock.set(Self.start.addingTimeInterval(62 * 60))
        let held = await runtime.refresh()

        XCTAssertEqual(resetsAvailable(first.lines), 1)
        XCTAssertEqual(resetsAvailable(rotated.lines), 1)
        XCTAssertEqual(resetsAvailable(held.lines), 1)
        XCTAssertEqual(http.requests.filter(\.isClaudeResetGrantsCheck).count, 2)
        XCTAssertEqual(http.requests.filter { $0.url.path == "/v1/oauth/token" }.count, 1)
    }

    func testEachAccountKeepsItsOwnHourlyCheck() async throws {
        let clock = TestClock(Self.start)
        let http = RoutingHTTPClient { request in
            switch request.url.path {
            case "/api/oauth/usage":
                guard request.url.query != nil else { return Self.usage() }
                return Self.grants(resetsLeft: request.headers["Authorization"] == "Bearer token-a" ? 1 : 2)
            default:
                return HTTPResponse(statusCode: 404, headers: [:], body: Data())
            }
        }
        let work = try makeRuntime(http: http, clock: clock)
        let personal = try makeRuntime(http: http, clock: clock, accessToken: "token-p")

        let workFirst = await work.refresh()
        let personalFirst = await personal.refresh()
        clock.set(Self.start.addingTimeInterval(5 * 60))
        _ = await work.refresh()
        _ = await personal.refresh()

        XCTAssertEqual(resetsAvailable(workFirst.lines), 1)
        XCTAssertEqual(resetsAvailable(personalFirst.lines), 2)
        XCTAssertEqual(
            http.requests.filter(\.isClaudeResetGrantsCheck).map { $0.headers["Authorization"] },
            ["Bearer token-a", "Bearer token-p"]
        )
    }

    // MARK: - Helpers

    private func makeRuntime(
        http: RoutingHTTPClient,
        clock: TestClock,
        accessToken: String = "token-a",
        expiresAt: Date? = nil
    ) throws -> AccountProviderRuntime {
        let account = Account(kind: .claude, label: "Work")
        let vault = InMemoryCredentialVault()
        try vault.save(
            .oauth(OAuthTokens(accessToken: accessToken, refreshToken: "refresh-a", expiresAt: expiresAt)),
            for: account.id
        )
        return AccountProviderRuntime(account: account, vault: vault, http: http, now: { clock.now })
    }

    private func usageQueries(_ http: RoutingHTTPClient) -> [String?] {
        http.requests.filter { $0.url.path == "/api/oauth/usage" }.map(\.url.query)
    }

    private func resetsAvailable(_ lines: [MetricLine]) -> Double? {
        guard case .values(_, let values, _, _) = lines.first(where: { $0.label == "Rate Limit Resets" }) else {
            return nil
        }
        return values.first?.number
    }

    private nonisolated static func usage() -> HTTPResponse {
        HTTPResponse(
            statusCode: 200, headers: [:],
            body: Data(#"{"five_hour":{"utilization":42,"resets_at":"2099-01-01T00:00:00.000Z"},"cedar_ember":null}"#.utf8)
        )
    }

    private nonisolated static func grants(resetsLeft: Int, endsAt: Date? = nil) -> HTTPResponse {
        let endsAtJSON = endsAt.map { "\"\(OpenUsageISO8601.string(from: $0))\"" } ?? "null"
        return HTTPResponse(
            statusCode: 200, headers: [:],
            body: Data(#"{"cedar_ember":{"eligible":true,"grants":[{"id":"g","resets_left":\#(resetsLeft),"ends_at":\#(endsAtJSON)}]}}"#.utf8)
        )
    }
}

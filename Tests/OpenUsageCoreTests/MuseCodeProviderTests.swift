import XCTest
@testable import OpenUsageCore

final class MuseCodeUsageMapperTests: XCTestCase {
    /// The shape Meta returned on 2026-10-27 (account fields replaced with obvious fakes).
    private let live = #"""
    {"api_key":"FAKE-KEY","base_url":"https://api.meta.ai/v1","has_payment_method":false,"require_payment":false,
     "is_subs_active":true,"can_subscribe":false,"show_subs_upsell":true,"user_full_name":"Fake Person",
     "user_email":"fake@example.com","user_avatar_url":"https://example.com/a.png","payment_method":null,"action_url":null,
     "subs_tier_id":"27681631238169137","subs_tier_name":"Muse Code Power Usage","is_subs_upgrade_available":true,
     "subs_usage":{"window":{"used_percent":37,"window_duration_mins":300,"resets_at":1793137636},
                   "weekly":{"used_percent":12,"resets_at":1793577600},"tier":"27681631238169137"}}
    """#

    func testMapsTheLiveShapeToSessionAndWeeklyMeters() throws {
        let mapped = try MuseCodeUsageMapper.map(Data(live.utf8))

        XCTAssertEqual(mapped.plan, "Muse Code Power Usage")
        XCTAssertEqual(mapped.lines.count, 2)
        XCTAssertEqual(mapped.lines[0], .progress(
            label: "Session", used: 37, limit: 100, format: .percent,
            resetsAt: Date(timeIntervalSince1970: 1_793_137_636), periodDurationMs: 300 * 60_000
        ))
        XCTAssertEqual(mapped.lines[1], .progress(
            label: "Weekly", used: 12, limit: 100, format: .percent,
            resetsAt: Date(timeIntervalSince1970: 1_793_577_600), periodDurationMs: 7 * 24 * 60 * 60 * 1000
        ))
    }

    func testNothingFromTheAccountLeaksIntoTheLines() throws {
        let mapped = try MuseCodeUsageMapper.map(Data(live.utf8))
        let text = String(describing: mapped)
        for secret in ["FAKE-KEY", "fake@example.com", "Fake Person", "example.com/a.png"] {
            XCTAssertFalse(text.contains(secret), secret)
        }
    }

    func testOverQuotaPercentIsKeptForTheRowToClamp() throws {
        let body = #"{"subs_tier_name":"Muse Code","subs_usage":{"window":{"used_percent":130,"window_duration_mins":300,"resets_at":1793137636},"weekly":{"used_percent":0,"resets_at":1793577600}}}"#
        guard case .progress(_, let used, _, _, _, _, _) = try MuseCodeUsageMapper.map(Data(body.utf8)).lines[0]
        else { return XCTFail("expected a meter") }
        XCTAssertEqual(used, 130)
    }

    func testAccountWithoutAllowanceYetReadsNoData() throws {
        let mapped = try MuseCodeUsageMapper.map(Data(#"{"is_subs_active":true,"subs_tier_name":"Muse Code"}"#.utf8))
        XCTAssertEqual(mapped.lines, [.noUsageData])
        XCTAssertEqual(mapped.plan, "Muse Code")
    }

    func testInactiveSubscriptionIsAClearError() {
        XCTAssertThrowsError(try MuseCodeUsageMapper.map(Data(#"{"is_subs_active":false}"#.utf8))) {
            XCTAssertEqual($0 as? MuseCodeUsageError, .noSubscription)
        }
    }

    func testMalformedBodiesAreInvalidNotZero() {
        for body in ["not json", "[]", #"{"subs_usage":{"window":{"resets_at":1}}}"#, #"{"subs_usage":{"window":{"used_percent":-5}}}"#] {
            XCTAssertThrowsError(try MuseCodeUsageMapper.map(Data(body.utf8)), body) {
                XCTAssertEqual($0 as? MuseCodeUsageError, .invalidResponse, body)
            }
        }
    }
}

@MainActor
final class MuseCodeRuntimeTests: XCTestCase {
    private let body = #"{"api_key":"SECRET-KEY","subs_tier_name":"Muse Code Power Usage","is_subs_active":true,"subs_usage":{"window":{"used_percent":37,"window_duration_mins":300,"resets_at":1793137636},"weekly":{"used_percent":12,"resets_at":1793577600}}}"#

    private func runtime(status: Int, body: String? = nil, throwing: Bool = false) throws -> (AccountProviderRuntime, RoutingHTTPClient) {
        let payload = Data((body ?? self.body).utf8)
        let http = RoutingHTTPClient { _ in
            if throwing { throw URLError(.notConnectedToInternet) }
            return HTTPResponse(statusCode: status, headers: [:], body: payload)
        }
        let account = Account(kind: .musecode, label: "Test")
        let vault = InMemoryCredentialVault()
        try vault.save(.oauth(OAuthTokens(accessToken: "signin-token")), for: account.id)
        return (AccountProviderRuntime(account: account, vault: vault, http: http), http)
    }

    func testRefreshPostsWithTheSignInTokenAndReturnsBothMeters() async throws {
        let (runtime, http) = try runtime(status: 200)

        let snapshot = await runtime.refresh()

        let request = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.absoluteString, "https://api.meta.ai/muse-code/key")
        XCTAssertEqual(request.headers["Authorization"], "Bearer signin-token")
        XCTAssertEqual(snapshot.plan, "Muse Code Power Usage")
        XCTAssertEqual(snapshot.lines.map(\.label), ["Session", "Weekly"])
        XCTAssertEqual(runtime.widgetDescriptors.map(\.metricLabel), ["Session", "Weekly"])
        XCTAssertFalse(String(describing: snapshot).contains("SECRET-KEY"), "the minted key is never kept")
    }

    func testAnExpiredSignInSaysToAddTheAccountAgain() async throws {
        let (runtime, _) = try runtime(status: 401, body: #"{"error":{"message":"Invalid or expired API key"}}"#)
        let snapshot = await runtime.refresh()
        XCTAssertEqual(snapshot.lines.first?.isError, true)
        guard case .badge(_, let text, _, _) = snapshot.lines[0] else { return XCTFail("expected an error badge") }
        XCTAssertEqual(text, "Muse Code sign-in expired. Add the account again.")
        XCTAssertFalse(text.contains("API key"), "no response text is echoed")
    }

    func testAServerErrorAndAMissingConnectionAreFriendly() async throws {
        let (server, _) = try runtime(status: 503, body: "oops")
        guard case .badge(_, let serverText, _, _) = await server.refresh().lines[0] else { return XCTFail() }
        XCTAssertEqual(serverText, "The provider request failed (HTTP 503).")

        let (offline, _) = try runtime(status: 0, throwing: true)
        guard case .badge(_, let offlineText, _, _) = await offline.refresh().lines[0] else { return XCTFail() }
        XCTAssertEqual(offlineText, "Connection failed. Check your internet connection and try again.")
    }

    func testResourceKeysAreSessionAndWeekly() {
        XCTAssertEqual(LimitsProjection.rowSuffixes(for: .musecode), ["session", "weekly"])
    }
}

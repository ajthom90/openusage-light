import Foundation
import XCTest
@testable import OpenUsage

@MainActor
final class OAuthRefreshPersistenceTests: XCTestCase {
    func testClaudeRefreshPersistsRotatedCredentialToVault() async throws {
        let account = Account(kind: .claude, label: "Claude")
        let vault = InMemoryCredentialVault()
        try vault.save(
            .oauth(OAuthTokens(accessToken: "old-access", refreshToken: "old-refresh", expiresAt: .distantPast)),
            for: account.id
        )
        let http = RoutingHTTPClient { request in
            if request.url.absoluteString == "https://platform.claude.com/v1/oauth/token" {
                return HTTPResponse(
                    statusCode: 200,
                    headers: [:],
                    body: Data(#"{"access_token":"new-access","refresh_token":"rotated-refresh","expires_in":3600}"#.utf8)
                )
            }
            return HTTPResponse(statusCode: 401, headers: [:], body: Data())
        }
        let runtime = AccountProviderRuntime(account: account, vault: vault, http: http)

        _ = await runtime.refresh()

        guard case .oauth(let saved)? = try vault.load(account.id) else {
            return XCTFail("Expected refreshed OAuth credential in the vault")
        }
        XCTAssertEqual(saved.accessToken, "new-access")
        XCTAssertEqual(saved.refreshToken, "rotated-refresh")
        XCTAssertNotNil(saved.expiresAt)
    }

    func testClaudePlanComesFromTheProfileAndIsFetchedOncePerToken() async throws {
        let account = Account(kind: .claude, label: "Claude")
        let vault = InMemoryCredentialVault()
        try vault.save(.oauth(OAuthTokens(accessToken: "access")), for: account.id)
        let http = RoutingHTTPClient { request in
            switch request.url.absoluteString {
            case "https://api.anthropic.com/api/oauth/usage":
                return HTTPResponse(statusCode: 200, headers: [:], body: Data(#"{"five_hour":{"utilization":12}}"#.utf8))
            case "https://api.anthropic.com/api/oauth/profile":
                let body = #"{"account":{"uuid":"a"},"organization":{"uuid":"o","organization_type":"claude_max","rate_limit_tier":"default_claude_max_20x"}}"#
                return HTTPResponse(statusCode: 200, headers: [:], body: Data(body.utf8))
            default:
                return HTTPResponse(statusCode: 404, headers: [:], body: Data())
            }
        }
        let runtime = AccountProviderRuntime(account: account, vault: vault, http: http)

        let first = await runtime.refresh()
        let second = await runtime.refresh()

        XCTAssertEqual(first.plan, "Max 20x")
        XCTAssertEqual(second.plan, "Max 20x")
        XCTAssertEqual(http.requests.filter { $0.url.path == "/api/oauth/profile" }.count, 1)
    }
}

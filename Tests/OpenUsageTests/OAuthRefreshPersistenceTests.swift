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
}

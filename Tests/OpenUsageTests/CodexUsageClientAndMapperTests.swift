import XCTest
@testable import OpenUsage

final class CodexUsageClientAndMapperTests: XCTestCase {
    func testRefreshEncodesReservedCharactersInRequestBody() async throws {
        let http = FakeHTTPClient(response: HTTPResponse(
            statusCode: 200,
            headers: [:],
            body: Data(#"{"access_token":"new-token"}"#.utf8)
        ))

        _ = try await CodexUsageClient(http: http).refreshToken("refresh token&=+/?%")

        let request = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(request.url, CodexUsageClient.refreshURL)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(
            String(data: try XCTUnwrap(request.body), encoding: .utf8),
            "grant_type=refresh_token&client_id=\(CodexUsageClient.clientID)" +
                "&refresh_token=refresh%20token%26%3D%2B%2F%3F%25"
        )
    }

    func testRefreshRejectsAnExpiredSession() async {
        let http = FakeHTTPClient(response: HTTPResponse(
            statusCode: 400,
            headers: [:],
            body: Data(#"{"error":{"code":"refresh_token_expired"}}"#.utf8)
        ))

        do {
            _ = try await CodexUsageClient(http: http).refreshToken("refresh")
            XCTFail("expected refreshToken to throw")
        } catch let error as CodexAuthError {
            XCTAssertEqual(error, .sessionExpired)
        } catch {
            XCTFail("expected CodexAuthError.sessionExpired, got \(error)")
        }
    }

    func testUsageMapperKeepsProviderReportedSessionLimit() throws {
        let response = HTTPResponse(
            statusCode: 200,
            headers: [:],
            body: Data(#"{"rate_limit":{"primary_window":{"used_percent":42,"reset_after_seconds":3600}}}"#.utf8)
        )
        let mapped = try CodexUsageMapper.mapUsageResponse(response)

        guard case .progress(_, let used, let limit, _, _, _, _) = mapped.lines.first(where: { $0.label == "Session" })
        else { return XCTFail("expected Session meter") }
        XCTAssertEqual(used, 42)
        XCTAssertEqual(limit, 100)
    }
}

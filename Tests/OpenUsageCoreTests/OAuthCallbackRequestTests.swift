import XCTest
@testable import OpenUsageCore

final class OAuthCallbackRequestTests: XCTestCase {
    private func evaluate(_ target: String, method: String = "GET") -> OAuthCallbackRequest.Outcome {
        OAuthCallbackRequest.evaluate("\(method) \(target) HTTP/1.1\r\nHost: localhost\r\n\r\n", path: "/auth/callback", state: "xyz")
    }

    func testACodeWithTheRightStateSucceeds() throws {
        let outcome = evaluate("/auth/callback?code=abc123&state=xyz")
        XCTAssertEqual(outcome.status, 200)
        XCTAssertEqual(try outcome.result.get(), "abc123")
    }

    func testTheWrongStateIsRejected() {
        let outcome = evaluate("/auth/callback?code=abc&state=other")
        XCTAssertEqual(outcome.status, 400)
        XCTAssertThrowsError(try outcome.result.get()) { XCTAssertEqual(($0 as? LoopbackCallbackError)?.errorDescription, LoopbackCallbackError.stateMismatch.errorDescription) }
    }

    func testAProviderErrorIsReportedWithItsReason() {
        let outcome = evaluate("/auth/callback?error=access_denied&state=xyz")
        XCTAssertEqual(outcome.status, 400)
        XCTAssertThrowsError(try outcome.result.get()) { XCTAssertEqual(($0 as? LoopbackCallbackError)?.errorDescription, "Authorization failed: access_denied") }
    }

    func testAMissingOrEmptyCodeIsInvalid() {
        for target in ["/auth/callback?state=xyz", "/auth/callback?code=&state=xyz"] {
            let outcome = evaluate(target)
            XCTAssertEqual(outcome.status, 400, target)
            XCTAssertThrowsError(try outcome.result.get(), target)
        }
    }

    func testOtherPathsAndMethodsAreNotTheCallback() {
        XCTAssertEqual(evaluate("/favicon.ico").status, 404)
        XCTAssertEqual(evaluate("/auth/callback?code=a&state=xyz", method: "POST").status, 405)
    }

    func testAResponseIsAWellFormedHTTPMessage() {
        let text = String(decoding: OAuthCallbackRequest.response(for: evaluate("/auth/callback?code=a&state=xyz")), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(text.contains("Connection: close"))
        XCTAssertTrue(text.hasSuffix("<p>Sign-in complete. You may close this page.</p>"))
        let declared = Int(text.components(separatedBy: "Content-Length: ")[1].prefix { $0.isNumber })
        XCTAssertEqual(declared, text.components(separatedBy: "\r\n\r\n")[1].utf8.count)
    }
}

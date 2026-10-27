#if os(Windows)
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OpenUsageCore
@testable import OpenUsageWindows

final class WinsockCallbackServerTests: XCTestCase {
    /// `localhost` can resolve to the IPv6 address first; the listener is IPv4 loopback, so ask for it directly.
    private func fetch(_ address: String) async throws -> (status: Int, body: String) {
        let url = URL(string: address.replacingOccurrences(of: "localhost", with: "127.0.0.1"))!
        let (data, response) = try await URLSession.shared.data(from: url)
        return ((response as! HTTPURLResponse).statusCode, String(decoding: data, as: UTF8.self))
    }

    private func start(port: UInt16? = nil) async throws -> any OAuthCallbackServer {
        try await WinsockCallbackServer.factory("xyz", port, "/auth/callback")
    }

    func testTheRedirectDeliversItsCode() async throws {
        let server = try await start()
        XCTAssertTrue(server.redirectURI.hasPrefix("http://localhost:"), server.redirectURI)
        XCTAssertTrue(server.redirectURI.hasSuffix("/auth/callback"))
        async let code = server.waitForCode()
        let page = try await fetch(server.redirectURI + "?code=abc123&state=xyz")
        XCTAssertEqual(page.status, 200)
        XCTAssertTrue(page.body.contains("Sign-in complete"), page.body)
        let delivered = try await code
        XCTAssertEqual(delivered, "abc123")
    }

    func testAWrongStateEndsTheSignInWithAnError() async throws {
        let server = try await start()
        async let code: String = server.waitForCode()
        let page = try await fetch(server.redirectURI + "?code=abc&state=wrong")
        XCTAssertEqual(page.status, 400)
        do { _ = try await code; XCTFail("expected a state mismatch") } catch {
            XCTAssertEqual((error as? LoopbackCallbackError)?.errorDescription, LoopbackCallbackError.stateMismatch.errorDescription)
        }
    }

    func testAStrayRequestIsIgnoredAndTheRealCallbackStillWorks() async throws {
        let server = try await start()
        async let code = server.waitForCode()
        let stray = try await fetch(server.redirectURI.replacingOccurrences(of: "/auth/callback", with: "/favicon.ico"))
        XCTAssertEqual(stray.status, 404)
        let page = try await fetch(server.redirectURI + "?code=real&state=xyz")
        XCTAssertEqual(page.status, 200)
        let delivered = try await code
        XCTAssertEqual(delivered, "real")
    }

    func testCancelEndsTheWait() async throws {
        let server = try await start()
        async let code: String = server.waitForCode()
        server.cancel()
        do { _ = try await code; XCTFail("expected a cancellation") } catch {
            XCTAssertEqual((error as? LoopbackCallbackError)?.errorDescription, LoopbackCallbackError.cancelled.errorDescription)
        }
    }

    func testAPortAlreadyInUseIsRefused() async throws {
        let first = try await start()
        defer { first.cancel() }
        let port = UInt16(first.redirectURI.split(separator: ":")[2].prefix { $0.isNumber })!
        do { _ = try await start(port: port); XCTFail("expected the port to be refused") } catch {
            guard case LoopbackCallbackError.listenerFailed = error else { return XCTFail("\(error)") }
        }
    }
}
#endif

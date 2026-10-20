import Foundation
import Network
import XCTest
@testable import OpenUsage

final class OAuthFoundationTests: XCTestCase {
    func testPKCEAppendixBChallenge() {
        XCTAssertEqual(
            PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
    }

    func testDeviceCodePollerHandlesPendingSlowDownAndSuccess() async throws {
        let results: [DeviceCodePollResult<String>] = [.pending, .slowDown, .complete("token")]
        let index = LockedCounter()
        let sleeps = LockedValues()
        let token = try await DeviceCodePoller.poll(
            interval: 1,
            expiresIn: 100,
            sleep: { seconds in sleeps.append(seconds) },
            request: { results[index.next()] }
        )

        XCTAssertEqual(token, "token")
        XCTAssertEqual(sleeps.values, [1, 6])
    }

    func testDeviceCodeExpiredTokenFails() async {
        do {
            _ = try await DeviceCodePoller.poll(
                interval: 1,
                expiresIn: 100,
                sleep: { _ in },
                request: { .failed("The device code expired.") as DeviceCodePollResult<String> }
            )
            XCTFail("Expected expired token to fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The device code expired.")
        }
    }

    func testLoopbackCallbackAcceptsCodeAndRejectsWrongState() async throws {
        let server = try await LoopbackCallbackServer.start(state: "expected")
        XCTAssertEqual(URLComponents(string: server.redirectURI)?.host, "localhost")
        let callback = Task { try await server.waitForCode() }
        let validURL = server.redirectURI
            .replacingOccurrences(of: "localhost", with: "127.0.0.1")
            + "?code=accepted&state=expected"
        let valid = try await URLSession.shared.data(from: URL(string: validURL)!)
        XCTAssertEqual((valid.1 as? HTTPURLResponse)?.statusCode, 200)
        let acceptedCode = try await callback.value
        XCTAssertEqual(acceptedCode, "accepted")

        let invalid = try await LoopbackCallbackServer.start(state: "expected")
        let rejected = Task { try await invalid.waitForCode() }
        let invalidURL = invalid.redirectURI
            .replacingOccurrences(of: "localhost", with: "127.0.0.1")
            + "?code=ignored&state=wrong"
        let response = try await URLSession.shared.data(from: URL(string: invalidURL)!)
        XCTAssertEqual((response.1 as? HTTPURLResponse)?.statusCode, 400)
        do {
            _ = try await rejected.value
            XCTFail("Expected state mismatch")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The sign-in response did not match this request.")
        }
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        defer { value += 1 }
        return value
    }
}

private final class LockedValues: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [TimeInterval] = []
    var values: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func append(_ value: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        stored.append(value)
    }
}

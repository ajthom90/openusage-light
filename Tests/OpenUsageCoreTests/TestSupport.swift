import Foundation
@testable import OpenUsageCore

final class RoutingHTTPClient: HTTPClient, @unchecked Sendable {
    private let recorded = Locked<[HTTPRequest]>(initialState: [])
    var requests: [HTTPRequest] { recorded.withLock { $0 } }
    private let handler: @Sendable (HTTPRequest) async throws -> HTTPResponse

    init(handler: @escaping @Sendable (HTTPRequest) async throws -> HTTPResponse) {
        self.handler = handler
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        recorded.withLock { $0.append(request) }
        return try await handler(request)
    }
}

/// A mutable clock so a test can advance `now` between runs to exercise time-based gates.
final class TestClock: @unchecked Sendable {
    private let value: Locked<Date>

    init(_ date: Date) { value = Locked(initialState: date) }

    var now: Date { value.withLock { $0 } }

    func set(_ date: Date) { value.withLock { $0 = date } }
}

/// A thread-safe value a stub HTTP handler can read while the test flips it.
final class TestSwitch<Value: Sendable>: @unchecked Sendable {
    private let locked: Locked<Value>

    init(_ value: Value) { locked = Locked(initialState: value) }

    var value: Value {
        get { locked.withLock { $0 } }
        set { locked.withLock { $0 = newValue } }
    }
}

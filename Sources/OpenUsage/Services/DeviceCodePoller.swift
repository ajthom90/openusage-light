import Foundation

enum DeviceCodePollResult<Value: Sendable>: Sendable {
    case pending
    case slowDown
    case complete(Value)
    case failed(String)
}

enum DeviceCodePoller {
    static func poll<Value: Sendable>(
        interval: TimeInterval,
        expiresIn: TimeInterval,
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        },
        request: @escaping @Sendable () async throws -> DeviceCodePollResult<Value>
    ) async throws -> Value {
        let deadline = now().addingTimeInterval(expiresIn)
        var delay = max(1, interval)
        while now() < deadline {
            try Task.checkCancellation()
            switch try await request() {
            case .pending:
                break
            case .slowDown:
                delay += 5
            case .complete(let value):
                return value
            case .failed(let message):
                throw DeviceCodeError(message)
            }
            try await sleep(min(delay, max(0, deadline.timeIntervalSince(now()))))
        }
        throw DeviceCodeError("Device sign-in expired.")
    }
}

struct DeviceCodeError: LocalizedError, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

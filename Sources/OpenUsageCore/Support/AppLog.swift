import Foundation

/// Subsystem tags that prefix every log line, keeping lines grep-friendly (`[refresh]`, `[cache]`,
/// `[plugin:claude]`, …). The raw value is the bracketed text and the `os.Logger` category.
package enum LogTag: String, Sendable {
    case refresh
    case cache
    case http
    case auth
    case keychain
    case menubar
    case updates
    case config
    case statusItem = "statusitem"
    case localAPI = "localapi"
    case subprocess
    case lifecycle
    case notifications

    /// Compound `[plugin:<id>]` / `[auth:<id>]` tags for per-provider lines.
    package static func plugin(_ id: String) -> String { "plugin:\(id)" }
    package static func auth(_ id: String) -> String { "auth:\(id)" }
}

/// The one consolidated logging facility, free of any platform logger. A single level floor governs
/// every sink. Each call:
///   1. drops the line immediately if its severity is below the current floor — before the message is
///      even built (so the `@autoclosure` truly defers) and before any redaction runs,
///   2. otherwise runs the message through `LogRedaction.redactLogMessage` as a lightweight last line
///      of defense, then hands the redacted line to every registered sink.
///
/// `redactLogMessage` is URL/body-unaware: any call site that logs a URL or response body MUST
/// pre-redact it via `LogRedaction.redactURL` / `bodyPreview`.
///
/// Sinks are installed by the platform layer (the Mac app wires `os.Logger` and a log file). Errors
/// (severity 0) always clear any floor, so they are never suppressed.
package enum AppLog {
    package enum Level: Int, Sendable {
        case error = 0
        case warn = 1
        case info = 2
        case debug = 3

        package var label: String {
            switch self {
            case .error: "ERROR"
            case .warn: "WARN"
            case .info: "INFO"
            case .debug: "DEBUG"
            }
        }
    }

    /// Receives one redacted line: its level, tag, message, and time.
    package typealias Sink = @Sendable (Level, String, String, Date) -> Void

    private struct State {
        var floor = Level.info.rawValue
        var sinks: [Sink] = []
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var state = State()

    /// Sets the severity floor: lines less severe than `level` are dropped.
    package static func setLevel(_ level: Level) {
        lock.lock()
        state.floor = level.rawValue
        lock.unlock()
    }

    /// Replaces the registered sinks.
    package static func setSinks(_ sinks: [Sink]) {
        lock.lock()
        state.sinks = sinks
        lock.unlock()
    }

    // MARK: - Public API

    /// `@autoclosure` defers the interpolation: a line below the current level floor is dropped before
    /// its message is built, so a `debug` line genuinely costs nothing when the level is Info.
    package static func error(_ tag: String, _ message: @autoclosure () -> String) { emit(.error, tag, message) }
    package static func warn(_ tag: String, _ message: @autoclosure () -> String) { emit(.warn, tag, message) }
    package static func info(_ tag: String, _ message: @autoclosure () -> String) { emit(.info, tag, message) }
    package static func debug(_ tag: String, _ message: @autoclosure () -> String) { emit(.debug, tag, message) }

    // Convenience overloads for the typed tags (the common case).
    package static func error(_ tag: LogTag, _ message: @autoclosure () -> String) { emit(.error, tag.rawValue, message) }
    package static func warn(_ tag: LogTag, _ message: @autoclosure () -> String) { emit(.warn, tag.rawValue, message) }
    package static func info(_ tag: LogTag, _ message: @autoclosure () -> String) { emit(.info, tag.rawValue, message) }
    package static func debug(_ tag: LogTag, _ message: @autoclosure () -> String) { emit(.debug, tag.rawValue, message) }

    // MARK: - Emit

    private static func emit(_ level: Level, _ tag: String, _ message: () -> String) {
        // Gate first: a line below the floor builds no message, runs no redaction, hits no sink.
        lock.lock()
        let snapshot = state
        lock.unlock()
        guard level.rawValue <= snapshot.floor, !snapshot.sinks.isEmpty else { return }

        let redacted = LogRedaction.redactLogMessage(message())
        let now = Date()
        for sink in snapshot.sinks { sink(level, tag, redacted, now) }
    }
}

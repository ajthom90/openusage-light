import Foundation
import os
import OpenUsageCore

/// The Mac half of `AppLog`: the user's `LogLevelSetting` as the level floor, and the `os.Logger` and
/// log-file sinks. The portable half (tags, level gate, redaction) lives in `OpenUsageCore`.
extension AppLog {
    /// The file sink. Injectable so tests can point it at a temp directory and assert what the level
    /// gate actually writes; production uses the shared `~/Library/Logs/OpenUsage/OpenUsage.log` appender.
    nonisolated(unsafe) static var sink: LogFile = .shared

    private static let loggerLock = NSLock()
    private nonisolated(unsafe) static var loggers: [String: Logger] = [:]

    /// Open/trim the file, seed the level, install the sinks, and emit one startup line. Call FIRST at
    /// launch, before any other subsystem logs.
    static func bootstrap() {
        sink.open()
        reloadLevel()
        let level = LogLevelSetting.current
        // Abbreviate `$HOME` to `~` so the path survives `redactLogMessage` (which masks `/Users/...`)
        // and the startup line actually self-documents where the log lives.
        let displayPath = (LogFile.url.path as NSString).abbreviatingWithTildeInPath
        info(LogTag.config.rawValue,
             "OpenUsage v\(AppInfo.version) starting (level=\(level.rawValue), log=\(displayPath))")
    }

    /// Re-read the persisted level and make sure the Mac sinks are installed. Invoked from the Settings
    /// picker `.onChange` so a level change applies live with no restart.
    static func reloadLevel() {
        reloadLevel(LogLevelSetting.current)
    }

    /// Apply a level directly, bypassing `UserDefaults`. The seam tests use to exercise the gate
    /// without racing on global `UserDefaults.standard` state.
    static func reloadLevel(_ level: LogLevelSetting) {
        installMacSinks()
        setLevel(coreLevel(level))
    }

    private static func coreLevel(_ level: LogLevelSetting) -> Level {
        switch level {
        case .error: .error
        case .warn: .warn
        case .info: .info
        case .debug: .debug
        }
    }

    private static func installMacSinks() {
        setSinks([
            { level, tag, message, date in
                logger(for: tag).log(level: osType(level), "[\(tag, privacy: .public)] \(message, privacy: .public)")
                AppLog.sink.append("\(OpenUsageISO8601.string(from: date)) [\(level.label)] [\(tag)] \(message)")
            }
        ])
    }

    private static func osType(_ level: Level) -> OSLogType {
        switch level {
        case .error: .error
        case .warn: .default
        case .info: .info
        case .debug: .debug
        }
    }

    private static func logger(for tag: String) -> Logger {
        loggerLock.lock()
        defer { loggerLock.unlock() }
        if let existing = loggers[tag] { return existing }
        let logger = Logger(subsystem: "OpenUsage", category: tag)
        loggers[tag] = logger
        return logger
    }
}

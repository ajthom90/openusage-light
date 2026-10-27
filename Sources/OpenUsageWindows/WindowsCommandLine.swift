#if os(Windows)
import Foundation
import OpenUsageCore

/// Where the Windows app keeps its saved state: `%APPDATA%\OpenUsage Light`, unless
/// `OPENUSAGE_LIGHT_DATA_DIR` names another directory (used by tests).
package enum WindowsPaths {
    package static func dataDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["OPENUSAGE_LIGHT_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = environment["APPDATA"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("AppData/Roaming", isDirectory: true)
        return base.appendingPathComponent("OpenUsage Light", isDirectory: true)
    }
}

extension LimitsCommand.Environment {
    /// The Windows app's own saved accounts and encrypted credentials. Never another tool's.
    package static func windowsLive(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        http: any HTTPClient = URLSessionHTTPClient()
    ) -> LimitsCommand.Environment {
        let directory = WindowsPaths.dataDirectory(environment: environment)
        return LimitsCommand.Environment(
            defaults: FileSettingsStore(directory: directory.appendingPathComponent("settings", isDirectory: true)),
            vault: DPAPICredentialVault(directory: directory.appendingPathComponent("credentials", isDirectory: true)),
            http: http,
            version: "0.1.0"
        )
    }
}

/// The Windows `openusage` command.
package enum WindowsCommandLine {
    package static func main(arguments: [String]) async -> Int32 {
        await LimitsCommand.main(arguments: arguments, environment: { .windowsLive() })
    }
}
#endif

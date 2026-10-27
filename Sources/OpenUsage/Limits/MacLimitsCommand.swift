import Foundation
import OpenUsageCore

extension LimitsCommand.Environment {
    /// The data of the OpenUsage Light app the command was installed from: its preferences domain and
    /// its Keychain service. Never another tool's.
    static func live() -> LimitsCommand.Environment {
        LimitsCommand.Environment(
            defaults: AppPreferences.defaults(),
            vault: KeychainCredentialVault(),
            version: AppInfo.version
        )
    }
}

/// The Mac `openusage` command, which the `openusage-cli` executable runs.
package enum OpenUsageCommandLine {
    package static func main(arguments: [String]) async -> Int32 {
        await LimitsCommand.main(arguments: arguments, environment: LimitsCommand.Environment.live)
    }
}

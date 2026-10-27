import Foundation
import OpenUsageCore

/// The `openusage` command: parse the arguments, run the engine against the app's own saved accounts,
/// and hand back what to print and how to exit. The `openusage-cli` executable is only a shell around
/// `LimitsCommand.main`, so the whole command is testable in-process.
@MainActor
package struct LimitsCommand {
    package init() {}

    struct Result: Equatable {
        var stdout = ""
        var stderr = ""
        var exitCode: Int32 = 0
    }

    enum ExitCode {
        static let invalidArguments: Int32 = 2
        static let refreshFailed: Int32 = 4
    }

    /// The command's world: where accounts, credentials and cached snapshots live. `live` is the
    /// installed app's; tests pass their own.
    struct Environment {
        var defaults: UserDefaults
        var vault: any CredentialVault
        var http: any HTTPClient = URLSessionHTTPClient()
        var now: () -> Date = Date.init

        /// The data of the OpenUsage Light app the command was installed from: its preferences domain
        /// and its Keychain service. Never another tool's.
        static func live() -> Environment {
            Environment(defaults: AppPreferences.defaults(), vault: KeychainCredentialVault())
        }
    }

    /// Entry point for the executable: runs the command, prints, and returns the exit code.
    package static func main(arguments: [String]) async -> Int32 {
        let result = await LimitsCommand().run(arguments: arguments, environment: Environment.live)
        if !result.stdout.isEmpty { FileHandle.standardOutput.write(Data((result.stdout + "\n").utf8)) }
        if !result.stderr.isEmpty { FileHandle.standardError.write(Data((result.stderr + "\n").utf8)) }
        return result.exitCode
    }

    /// `environment` is only called once the arguments are valid, so `--help` never touches saved data.
    func run(arguments: [String], environment: () -> Environment) async -> Result {
        switch LimitsArguments.parse(arguments) {
        case .failure(let invalid):
            return Result(stderr: "openusage: \(invalid.message)\n\n\(LimitsArguments.usage)", exitCode: ExitCode.invalidArguments)
        case .success(.help):
            return Result(stdout: LimitsArguments.usage)
        case .success(.version):
            return Result(stdout: AppInfo.version)
        case .success(.limits(let provider, let force)):
            return await limits(provider: provider, force: force, environment: environment())
        }
    }

    private func limits(provider: String?, force: Bool, environment: Environment) async -> Result {
        let accounts = AccountStore(defaults: environment.defaults, vault: environment.vault)
        let service = LimitsService(
            accounts: accounts.accounts,
            vault: environment.vault,
            cache: ProviderSnapshotCache(userDefaults: environment.defaults),
            savedOrder: LayoutPersistence.savedProviderOrder(defaults: environment.defaults),
            http: environment.http,
            now: environment.now
        )
        do {
            let outcome = try await service.run(provider: provider, force: force)
            let note = accounts.accounts.isEmpty ? "No accounts yet. Add one from the Accounts screen in OpenUsage Light." : ""
            return Result(
                stdout: try outcome.envelope.json(),
                stderr: note,
                exitCode: outcome.hadFailures ? ExitCode.refreshFailed : 0
            )
        } catch LimitsService.Failure.unknownProvider(let name) {
            return Result(stderr: "openusage: no provider or account named \"\(name)\".", exitCode: ExitCode.invalidArguments)
        } catch {
            return Result(stderr: "openusage: \(error.localizedDescription)", exitCode: ExitCode.refreshFailed)
        }
    }
}

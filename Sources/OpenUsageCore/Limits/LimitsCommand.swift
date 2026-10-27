import Foundation

/// The `openusage` command: parse the arguments, run the engine against the app's own saved accounts,
/// and hand back what to print and how to exit. The `openusage-cli` executable is only a shell around
/// `LimitsCommand.main`, so the whole command is testable in-process. Platform-neutral: each platform
/// supplies the `Environment` (where its saved accounts and credentials are).
@MainActor
package struct LimitsCommand {
    package init() {}

    package struct Result: Equatable {
        package var stdout = ""
        package var stderr = ""
        package var exitCode: Int32 = 0

        package init(stdout: String = "", stderr: String = "", exitCode: Int32 = 0) {
            self.stdout = stdout
            self.stderr = stderr
            self.exitCode = exitCode
        }
    }

    package enum ExitCode {
        package static let invalidArguments: Int32 = 2
        package static let refreshFailed: Int32 = 4
    }

    /// The command's world: where accounts, credentials and cached snapshots live. Each platform's
    /// `live` environment is its installed app's; tests pass their own.
    package struct Environment {
        package var defaults: any SettingsStore
        package var vault: any CredentialVault
        package var http: any HTTPClient = URLSessionHTTPClient()
        package var now: () -> Date = Date.init
        /// Printed by `--version`.
        package var version = "0.1.0"

        package init(
            defaults: any SettingsStore,
            vault: any CredentialVault,
            http: any HTTPClient = URLSessionHTTPClient(),
            now: @escaping () -> Date = Date.init,
            version: String = "0.1.0"
        ) {
            self.defaults = defaults
            self.vault = vault
            self.http = http
            self.now = now
            self.version = version
        }
    }

    /// Entry point for an executable: runs the command, prints, and returns the exit code.
    package static func main(arguments: [String], environment: () -> Environment) async -> Int32 {
        let result = await LimitsCommand().run(arguments: arguments, environment: environment)
        if !result.stdout.isEmpty { FileHandle.standardOutput.write(Data((result.stdout + "\n").utf8)) }
        if !result.stderr.isEmpty { FileHandle.standardError.write(Data((result.stderr + "\n").utf8)) }
        return result.exitCode
    }

    /// `environment` is only called once the arguments are valid, so `--help` never touches saved data.
    package func run(arguments: [String], environment: () -> Environment) async -> Result {
        switch LimitsArguments.parse(arguments) {
        case .failure(let invalid):
            return Result(stderr: "openusage: \(invalid.message)\n\n\(LimitsArguments.usage)", exitCode: ExitCode.invalidArguments)
        case .success(.help):
            return Result(stdout: LimitsArguments.usage)
        case .success(.limits(let provider, let force)):
            return await limits(provider: provider, force: force, environment: environment())
        case .success(.version):
            return Result(stdout: environment().version)
        }
    }

    private func limits(provider: String?, force: Bool, environment: Environment) async -> Result {
        let accounts = AccountStore(defaults: environment.defaults, vault: environment.vault)
        let service = LimitsService(
            accounts: accounts.accounts,
            vault: environment.vault,
            cache: ProviderSnapshotCache(userDefaults: environment.defaults),
            savedOrder: SavedDashboardOrder.providerOrder(in: environment.defaults),
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

#if os(Windows)
import XCTest
@testable import OpenUsageCore
@testable import OpenUsageWindows

final class WindowsPlatformTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpenUsageWindowsTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testDPAPIRoundTripsAndTheFileIsNotPlainText() throws {
        let vault = DPAPICredentialVault(directory: directory)
        let id = Foundation.UUID()
        let credential = AccountCredential.oauth(OAuthTokens(
            accessToken: "access-" + String(repeating: "a", count: 4000), refreshToken: "refresh-token", extras: ["k": "v"]
        ))

        XCTAssertNil(try vault.load(id))
        try vault.save(credential, for: id)
        XCTAssertEqual(try vault.load(id), credential, "a credential larger than Credential Manager's limit round-trips")

        let onDisk = try Data(contentsOf: directory.appendingPathComponent(id.uuidString.lowercased() + ".credential"))
        XCTAssertNil(String(decoding: onDisk, as: UTF8.self).range(of: "refresh-token"))

        try vault.delete(id)
        XCTAssertNil(try vault.load(id))
        XCTAssertNoThrow(try vault.delete(id), "deleting an absent credential is not an error")
    }

    func testDataDirectoryFollowsOverrideThenAppData() {
        XCTAssertEqual(
            WindowsPaths.dataDirectory(environment: ["OPENUSAGE_LIGHT_DATA_DIR": "C:\\Temp\\x", "APPDATA": "C:\\Users\\a\\AppData\\Roaming"]).lastPathComponent,
            "x"
        )
        XCTAssertEqual(
            WindowsPaths.dataDirectory(environment: ["APPDATA": "C:\\Users\\a\\AppData\\Roaming"]).lastPathComponent,
            "OpenUsage Light"
        )
    }

    /// Real HTTPS from Windows: a made-up OpenRouter key must come back as a friendly failure (exit 4)
    /// without the key anywhere in the output. Needs the network, so it runs only when asked for.
    func testRealHTTPSWithABogusKeyFailsFriendly() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["OPENUSAGE_NETWORK_TESTS"] == "1", "set OPENUSAGE_NETWORK_TESTS=1")
        let settings = FileSettingsStore(directory: directory.appendingPathComponent("settings"))
        let vault = DPAPICredentialVault(directory: directory.appendingPathComponent("credentials"))
        let bogus = "sk-or-not-a-real-key-\(UUID().uuidString)"
        await MainActor.run {
            _ = AccountStore(defaults: settings, vault: vault).add(kind: .openrouter, label: "Test", credential: .apiKey(bogus))
        }

        let result = await LimitsCommand().run(arguments: ["--force"], environment: {
            LimitsCommand.Environment(defaults: settings, vault: vault)
        })

        XCTAssertEqual(result.exitCode, LimitsCommand.ExitCode.refreshFailed, result.stdout)
        XCTAssertTrue(result.stdout.contains("\"errors\""))
        XCTAssertFalse(result.stdout.contains(bogus))
        XCTAssertFalse(result.stderr.contains(bogus))
    }
}
#endif

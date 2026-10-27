import XCTest
@testable import OpenUsageCore

@MainActor
final class LimitsCommandTests: XCTestCase {
    private let creditsBody = #"{"data":{"total_credits":100,"total_usage":22.23}}"#
    private let keyBody = #"{"data":{"usage_daily":1.5,"usage_weekly":4,"usage_monthly":12,"limit":1,"limit_remaining":0.25,"is_free_tier":false}}"#

    private func makeDefaults() -> any SettingsStore {
        FileSettingsStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("LimitsCommandTests-\(UUID().uuidString)", isDirectory: true))
    }

    private func environment(
        defaults: any SettingsStore,
        vault: InMemoryCredentialVault,
        clock: TestClock,
        http: RoutingHTTPClient
    ) -> LimitsCommand.Environment {
        LimitsCommand.Environment(defaults: defaults, vault: vault, http: http, now: { clock.now })
    }

    private func run(_ arguments: [String], _ environment: LimitsCommand.Environment) async -> LimitsCommand.Result {
        await LimitsCommand().run(arguments: arguments, environment: { environment })
    }

    private func http(failing: TestSwitch<Bool> = TestSwitch(false)) -> RoutingHTTPClient {
        RoutingHTTPClient { [creditsBody, keyBody] request in
            if failing.value { return HTTPResponse(statusCode: 500, headers: [:], body: Data()) }
            let body = request.url.absoluteString == OpenRouterUsageClient.creditsURL ? creditsBody : keyBody
            return HTTPResponse(statusCode: 200, headers: [:], body: Data(body.utf8))
        }
    }

    private func addAccount(_ defaults: any SettingsStore, _ vault: InMemoryCredentialVault, label: String) -> Account {
        AccountStore(defaults: defaults, vault: vault).add(kind: .openrouter, label: label, credential: .apiKey("sk-secret-key"))
    }

    func testRefreshesAnEmptyCacheThenReusesItUntilItExpires() async throws {
        let defaults = makeDefaults()
        let vault = InMemoryCredentialVault()
        _ = addAccount(defaults, vault, label: "Work")
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let http = http()
        let env = environment(defaults: defaults, vault: vault, clock: clock, http: http)

        let first = await run([], env)
        XCTAssertEqual(first.exitCode, 0)
        XCTAssertTrue(first.stdout.contains(#""balance""#), first.stdout)
        let afterFirst = http.requests.count
        XCTAssertGreaterThan(afterFirst, 0)

        clock.set(clock.now.addingTimeInterval(299))
        _ = await run([], env)
        XCTAssertEqual(http.requests.count, afterFirst, "a snapshot under five minutes old is reused")

        clock.set(clock.now.addingTimeInterval(2))
        _ = await run([], env)
        XCTAssertGreaterThan(http.requests.count, afterFirst, "a stale snapshot is refreshed")
    }

    func testForceRefreshesAFreshSnapshot() async {
        let defaults = makeDefaults()
        let vault = InMemoryCredentialVault()
        _ = addAccount(defaults, vault, label: "Work")
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let http = http()
        let env = environment(defaults: defaults, vault: vault, clock: clock, http: http)

        _ = await run([], env)
        let afterFirst = http.requests.count
        _ = await run(["--force"], env)
        XCTAssertGreaterThan(http.requests.count, afterFirst)
    }

    func testFailedRefreshKeepsTheLastGoodSnapshotAndExitsFour() async throws {
        let defaults = makeDefaults()
        let vault = InMemoryCredentialVault()
        let account = addAccount(defaults, vault, label: "Work")
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let failing = TestSwitch(false)
        let env = environment(defaults: defaults, vault: vault, clock: clock, http: http(failing: failing))

        _ = await run([], env)
        failing.value = true
        clock.set(clock.now.addingTimeInterval(600))
        let result = await run([], env)

        XCTAssertEqual(result.exitCode, LimitsCommand.ExitCode.refreshFailed)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any])
        let providers = try XCTUnwrap(json["providers"] as? [String: Any])
        let kept = try XCTUnwrap(providers[account.cardID] as? [String: Any])
        XCTAssertEqual(kept["stale"] as? Bool, true)
        let errors = try XCTUnwrap(json["errors"] as? [[String: String]])
        XCTAssertEqual(errors.first?["providerId"], account.cardID)
        XCTAssertFalse(try XCTUnwrap(errors.first?["message"]).isEmpty)
    }

    func testOutputNeverCarriesTheCredential() async {
        let defaults = makeDefaults()
        let vault = InMemoryCredentialVault()
        _ = addAccount(defaults, vault, label: "Work")
        let result = await run(["--force"], environment(
            defaults: defaults, vault: vault, clock: TestClock(Date(timeIntervalSince1970: 1_800_000_000)), http: http()
        ))
        XCTAssertFalse(result.stdout.contains("sk-secret-key"))
        XCTAssertFalse(result.stderr.contains("sk-secret-key"))
    }

    func testProviderNameSelectsEveryAccountOfItAndAccountIdSelectsOne() async throws {
        let defaults = makeDefaults()
        let vault = InMemoryCredentialVault()
        let first = addAccount(defaults, vault, label: "One")
        let second = addAccount(defaults, vault, label: "Two")
        let env = environment(defaults: defaults, vault: vault, clock: TestClock(Date(timeIntervalSince1970: 1_800_000_000)), http: http())

        let family = try JSONDecoder.limits.decode(LimitsEnvelope.self, from: Data(await run(["openrouter"], env).stdout.utf8))
        XCTAssertEqual(family.order, [first.cardID, second.cardID])

        let one = try JSONDecoder.limits.decode(LimitsEnvelope.self, from: Data(await run([second.cardID], env).stdout.utf8))
        XCTAssertEqual(one.order, [second.cardID])
    }

    func testUnknownProviderIsAnArgumentError() async {
        let defaults = makeDefaults()
        let vault = InMemoryCredentialVault()
        _ = addAccount(defaults, vault, label: "Work")
        let result = await run(["claude"], environment(
            defaults: defaults, vault: vault, clock: TestClock(Date(timeIntervalSince1970: 1_800_000_000)), http: http()
        ))
        XCTAssertEqual(result.exitCode, LimitsCommand.ExitCode.invalidArguments)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("claude"))
    }

    func testAccountsFollowTheSavedDashboardOrder() async throws {
        let defaults = makeDefaults()
        let vault = InMemoryCredentialVault()
        let first = addAccount(defaults, vault, label: "One")
        let second = addAccount(defaults, vault, label: "Two")
        defaults.set(try JSONEncoder().encode([second.cardID, first.cardID]), forKey: "\(SavedDashboardOrder.defaultStorageKey).providerOrder")
        let env = environment(defaults: defaults, vault: vault, clock: TestClock(Date(timeIntervalSince1970: 1_800_000_000)), http: http())

        let result = try JSONDecoder.limits.decode(LimitsEnvelope.self, from: Data(await run([], env).stdout.utf8))
        XCTAssertEqual(result.order, [second.cardID, first.cardID])
    }

    func testNoAccountsPrintsAnEmptyDocumentAndSucceeds() async throws {
        let result = await run([], environment(
            defaults: makeDefaults(), vault: InMemoryCredentialVault(),
            clock: TestClock(Date(timeIntervalSince1970: 1_800_000_000)), http: http()
        ))
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(try JSONDecoder.limits.decode(LimitsEnvelope.self, from: Data(result.stdout.utf8)).providers.count, 0)
        XCTAssertFalse(result.stderr.isEmpty)
    }

    func testHelpNeverOpensSavedData() async {
        var opened = false
        let result = await LimitsCommand().run(arguments: ["--help"], environment: {
            opened = true
            return .init(defaults: FileSettingsStore(directory: FileManager.default.temporaryDirectory), vault: InMemoryCredentialVault())
        })
        XCTAssertFalse(opened)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.hasPrefix("Usage: openusage"))
    }
}

private extension JSONDecoder {
    static var limits: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let date = OpenUsageISO8601.date(from: value) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: value))
            }
            return date
        }
        return decoder
    }
}

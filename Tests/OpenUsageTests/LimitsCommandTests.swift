import XCTest
@testable import OpenUsage
@testable import OpenUsageCore

/// Every public resource key is read from a dashboard row, so a row renamed in a runtime would
/// silently drop its field from the document. This fails first.
@MainActor
final class LimitsRowsTests: XCTestCase {
    func testEveryResourceKeyNamesARealDashboardRow() {
        for kind in ProviderKind.allCases {
            let runtime = AccountProviderRuntime(account: Account(kind: kind, label: "Work"), vault: InMemoryCredentialVault())
            let prefix = runtime.provider.id.count + 1
            let rows = Set(runtime.widgetDescriptors.map { String($0.id.dropFirst(prefix)) })
            for suffix in LimitsProjection.rowSuffixes(for: kind) {
                XCTAssertTrue(rows.contains(suffix), "\(kind.rawValue) has no dashboard row \"\(suffix)\"")
            }
        }
    }
}

@MainActor
final class LimitsCommandTests: XCTestCase {
    private let creditsBody = #"{"data":{"total_credits":100,"total_usage":22.23}}"#
    private let keyBody = #"{"data":{"usage_daily":1.5,"usage_weekly":4,"usage_monthly":12,"limit":1,"limit_remaining":0.25,"is_free_tier":false}}"#

    private func makeDefaults() -> UserDefaults {
        let suite = "OpenUsageTests.LimitsCommand.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func environment(
        defaults: UserDefaults,
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

    private func addAccount(_ defaults: UserDefaults, _ vault: InMemoryCredentialVault, label: String) -> Account {
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
        LayoutPersistence(defaults: defaults, storageKey: LayoutStore.defaultStorageKey)
            .saveProviderOrder([second.cardID, first.cardID])
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
            return .init(defaults: .standard, vault: InMemoryCredentialVault())
        })
        XCTAssertFalse(opened)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.hasPrefix("Usage: openusage"))
    }
}

final class AppPreferencesTests: XCTestCase {
    func testFindsTheEnclosingAppsBundleIdentifierThroughASymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AppPreferencesTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("Fake.app/Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.example.fake", "CFBundleExecutable": "tool", "CFBundlePackageType": "APPL"]
        try (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))
        let tool = contents.appendingPathComponent("MacOS/openusage-cli")
        try Data().write(to: tool)
        let link = root.appendingPathComponent("openusage")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: tool)

        XCTAssertEqual(AppPreferences.bundleIdentifier(containing: tool), "com.example.fake")
        XCTAssertEqual(AppPreferences.bundleIdentifier(containing: link), "com.example.fake")
        XCTAssertNil(AppPreferences.bundleIdentifier(containing: FileManager.default.temporaryDirectory.appendingPathComponent("tool")))
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

import XCTest
@testable import OpenUsageCore

@MainActor
final class DashboardModelTests: XCTestCase {
    private let creditsBody = #"{"data":{"total_credits":100,"total_usage":22.23}}"#
    private let keyBody = #"{"data":{"usage_daily":1.5,"usage_weekly":4,"usage_monthly":12,"limit":1,"limit_remaining":0.25,"is_free_tier":false}}"#

    private func makeSettings() -> FileSettingsStore {
        FileSettingsStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("DashboardModelTests-\(UUID().uuidString)", isDirectory: true))
    }

    private func http(failing: TestSwitch<Bool> = TestSwitch(false)) -> RoutingHTTPClient {
        RoutingHTTPClient { [creditsBody, keyBody] request in
            if failing.value { return HTTPResponse(statusCode: 500, headers: [:], body: Data()) }
            let body = request.url.absoluteString == OpenRouterUsageClient.creditsURL ? creditsBody : keyBody
            return HTTPResponse(statusCode: 200, headers: [:], body: Data(body.utf8))
        }
    }

    private func model(
        _ settings: FileSettingsStore, vault: InMemoryCredentialVault, clock: TestClock, http: RoutingHTTPClient
    ) -> DashboardModel {
        DashboardModel(
            accounts: AccountStore(defaults: settings, vault: vault), settings: settings, http: http, now: { clock.now }
        )
    }

    func testRefreshFillsRowsForTheAccountInSavedOrder() async {
        let settings = makeSettings()
        let vault = InMemoryCredentialVault()
        let store = AccountStore(defaults: settings, vault: vault)
        let first = store.add(kind: .openrouter, label: "One", credential: .apiKey("k1"))
        let second = store.add(kind: .openrouter, label: "Two", credential: .apiKey("k2"))
        settings.set(try! JSONEncoder().encode([second.cardID, first.cardID]), forKey: "\(SavedDashboardOrder.defaultStorageKey).providerOrder")
        let model = model(settings, vault: vault, clock: TestClock(Date(timeIntervalSince1970: 1_800_000_000)), http: http())
        XCTAssertEqual(model.sections.map(\.account), ["Two", "One"], "saved order wins over the order added")
        XCTAssertTrue(model.sections.allSatisfy { $0.rows.isEmpty }, "no data until the first refresh")

        await model.refresh()

        XCTAssertEqual(model.sections.map(\.account), ["Two", "One"])
        let labels = model.sections[0].rows.map(\.label)
        XCTAssertTrue(labels.contains("Balance"), "\(labels)")
        XCTAssertNil(model.sections[0].notice)
        XCTAssertFalse(model.sections[0].outdated)
        XCTAssertNotNil(model.lastRefreshed)
    }

    func testAFailedRefreshKeepsLastRowsAndShowsTheReason() async {
        let settings = makeSettings()
        let vault = InMemoryCredentialVault()
        _ = AccountStore(defaults: settings, vault: vault).add(kind: .openrouter, label: "Work", credential: .apiKey("k"))
        let failing = TestSwitch(false)
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let model = model(settings, vault: vault, clock: clock, http: http(failing: failing))
        await model.refresh()
        let before = model.sections[0].rows

        failing.value = true
        clock.set(clock.now.addingTimeInterval(600))
        await model.refresh()

        XCTAssertEqual(model.sections[0].rows, before, "the last good rows stay on screen")
        XCTAssertNotNil(model.sections[0].notice)
    }

    func testOutdatedOnceTwoRefreshesAreMissed() async {
        let settings = makeSettings()
        let vault = InMemoryCredentialVault()
        _ = AccountStore(defaults: settings, vault: vault).add(kind: .openrouter, label: "Work", credential: .apiKey("k"))
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let model = model(settings, vault: vault, clock: clock, http: http())
        await model.refresh()
        XCTAssertFalse(model.sections[0].outdated)

        clock.set(clock.now.addingTimeInterval(RefreshSetting.interval * 2 + 1))
        model.reload()
        XCTAssertTrue(model.sections[0].outdated)
    }

    func testReloadPicksUpAnAddedAccountWithoutLosingRows() async {
        let settings = makeSettings()
        let vault = InMemoryCredentialVault()
        let store = AccountStore(defaults: settings, vault: vault)
        _ = store.add(kind: .openrouter, label: "One", credential: .apiKey("k1"))
        let model = DashboardModel(accounts: store, settings: settings, http: http(), now: { Date(timeIntervalSince1970: 1_800_000_000) })
        await model.refresh()
        let rows = model.sections[0].rows

        _ = store.add(kind: .openrouter, label: "Two", credential: .apiKey("k2"))
        model.reload()

        XCTAssertEqual(model.sections.map(\.account), ["One", "Two"], "a new account goes to the bottom")
        XCTAssertEqual(model.sections[0].rows, rows)
    }
}

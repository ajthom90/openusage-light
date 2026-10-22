import XCTest
@testable import OpenUsage

/// The in-popover screen mode (dashboard / Accounts / Settings) and its `isEditing` bridge,
/// which older call sites still drive Accounts through.
@MainActor
final class PopoverScreenTests: XCTestCase {
    func testStartsOnDashboard() {
        let store = makeStore("Default")
        XCTAssertEqual(store.screen, .dashboard)
        XCTAssertFalse(store.isEditing)
    }

    func testIsEditingBridgesAccountsScreen() {
        let store = makeStore("Bridge")

        store.isEditing = true
        XCTAssertEqual(store.screen, .accounts)

        store.isEditing = false
        XCTAssertEqual(store.screen, .dashboard)
    }

    func testSettingsScreenIsNotEditing() {
        let store = makeStore("Settings")

        store.screen = .settings
        XCTAssertFalse(store.isEditing)
    }

    func testScreensReplaceEachOther() {
        let store = makeStore("Switch")

        store.screen = .accounts
        store.screen = .settings
        XCTAssertEqual(store.screen, .settings)
        XCTAssertFalse(store.isEditing)

        store.screen = .accounts
        XCTAssertTrue(store.isEditing)
    }

    func testAccountsSlidesInBetweenDashboardAndSettings() {
        XCTAssertLessThan(PopoverScreen.dashboard.slideRank, PopoverScreen.accounts.slideRank)
        XCTAssertLessThan(PopoverScreen.accounts.slideRank, PopoverScreen.settings.slideRank)
    }

    private func makeStore(_ name: String) -> LayoutStore {
        let suiteName = "OpenUsageTests.PopoverScreen.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return LayoutStore(registry: .mock, defaults: defaults, storageKey: "layout")
    }
}

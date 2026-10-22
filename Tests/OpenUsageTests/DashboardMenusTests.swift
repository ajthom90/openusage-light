import XCTest
@testable import OpenUsage

/// Right-click is the only way to act on the dashboard: each menu holds what a click or hover used to.
@MainActor
final class DashboardMenusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let claude = Provider(
        id: "claude@1", displayName: "Claude", icon: .providerMark("claude"), accountLabel: "Personal", links: ProviderKind.claude.links
    )

    private func titles(_ sections: DashboardMenus.Sections) -> [[String]] {
        sections.map { $0.map(\.title) }
    }

    private func account(resetExpiries: [Date]? = nil) -> DashboardAccount {
        var resets: WidgetData?
        if let resetExpiries {
            var data = WidgetData(title: "Rate Limit Resets", icon: .providerMark("claude"), kind: .count, used: 2, limit: nil)
            data.values = [MetricValue(number: 2, kind: .count, label: "available")]
            data.showsResetExpiries = true
            data.expiriesAt = resetExpiries
            resets = data
        }
        return DashboardAccount(provider: claude, lines: [], resets: resets)
    }

    func testTheProviderMenuRefreshesManagesAndOpensTheLinks() {
        let other = Provider(id: "claude@2", displayName: "Claude", icon: .providerMark("claude"), accountLabel: "AM 1")
        let family = DashboardFamily(id: "claude", provider: claude, accounts: [account(), DashboardAccount(provider: other, lines: [])])
        let menu = DashboardMenus.provider(family)

        XCTAssertEqual(titles(menu), [["Refresh"], ["Manage Accounts…"], ["Status Page", "Usage Dashboard"]])
        XCTAssertEqual(menu[0][0].command, .refresh(["claude@1", "claude@2"]))
        XCTAssertEqual(menu[2].map(\.command), [
            .open(URL(string: "https://status.anthropic.com/")!),
            .open(URL(string: "https://claude.ai/settings/usage")!),
        ])
    }

    func testThePlainAccountMenu() {
        let menu = DashboardMenus.account(account(), status: nil, canShare: true, canClaimReset: false, hasHiddenMetrics: false, now: now)
        XCTAssertEqual(titles(menu), [["Refresh", "Rename", "Edit Account…"], ["Share Screenshot"]])
        XCTAssertEqual(menu.flatMap { $0 }.map(\.command), [
            .refresh(["claude@1"]), .rename("claude@1"), .editAccount("claude@1"), .shareScreenshot("claude@1"),
        ])
    }

    /// Without hover, the menu is the only place that says why the account line shows a warning, when
    /// the next reset expires, and that metrics are hidden.
    func testTheAccountMenuExplainsItsStatusUsesTheSoonestResetAndShowsHiddenMetrics() {
        let soonest = now.addingTimeInterval(6 * 86_400)
        let menu = DashboardMenus.account(
            account(resetExpiries: [now.addingTimeInterval(20 * 86_400), soonest, now.addingTimeInterval(-60)]),
            status: "Couldn't refresh. Check your connection.",
            canShare: true,
            canClaimReset: true,
            hasHiddenMetrics: true,
            now: now
        )
        let useReset = "Use a Reset (Expires \(DashboardMenus.expiryDate(soonest, now: now)))…"

        XCTAssertEqual(titles(menu), [
            ["Couldn't refresh. Check your connection."],
            ["Refresh", "Rename", "Edit Account…"],
            ["Share Screenshot"],
            [useReset, "Show Hidden Metrics"],
        ])
        XCTAssertNil(menu[0][0].command, "the status is a disabled line")
        XCTAssertEqual(menu[3][0].command, .useReset(accountID: "claude@1", expiry: soonest))
        XCTAssertEqual(menu[3][1].command, .showHiddenMetrics("claude@1"))
    }

    func testAResetThatCantBeClaimedStillShowsItsExpiryDisabled() {
        let soonest = now.addingTimeInterval(3 * 86_400)
        let menu = DashboardMenus.account(
            account(resetExpiries: [soonest]), status: nil, canShare: false, canClaimReset: false, hasHiddenMetrics: false, now: now
        )
        XCTAssertEqual(titles(menu).last, ["Use a Reset (Expires \(DashboardMenus.expiryDate(soonest, now: now)))…"])
        XCTAssertNil(menu.last?.first?.command)

        let unknown = DashboardMenus.account(
            account(resetExpiries: []), status: nil, canShare: false, canClaimReset: true, hasHiddenMetrics: false, now: now
        )
        XCTAssertEqual(titles(unknown).last, ["Use a Reset…"])
        XCTAssertNil(unknown.last?.first?.command, "no expiry, nothing to claim")
    }

    func testTheExpiryDateNamesTheYearOnlyWhenItIsNotThisOne() {
        let calendar = Calendar.current
        let thisYear = calendar.date(byAdding: .day, value: 3, to: calendar.startOfDay(for: now))!
        let nextYear = calendar.date(byAdding: .year, value: 1, to: thisYear)!
        let year = String(calendar.component(.year, from: nextYear))
        XCTAssertFalse(DashboardMenus.expiryDate(thisYear, now: now).contains(String(calendar.component(.year, from: thisYear))))
        XCTAssertTrue(DashboardMenus.expiryDate(nextYear, now: now).contains(year))
    }

    func testTheMetricMenuStarsAndHides() {
        let data = WidgetData(title: "Weekly", icon: .providerMark("claude"), kind: .percent, used: 10, limit: 100)
        var descriptor = WidgetDescriptor(id: "claude@1.weekly", providerID: "claude@1", metricLabel: "Weekly", sample: data)

        XCTAssertEqual(titles(DashboardMenus.metric(descriptor, isStarred: false)), [["Star for Menu Bar", "Hide"]])
        XCTAssertEqual(titles(DashboardMenus.metric(descriptor, isStarred: true)), [["Unstar", "Hide"]])
        XCTAssertEqual(DashboardMenus.metric(descriptor, isStarred: true)[0].map(\.command), [
            .toggleStar("claude@1.weekly"), .hide("claude@1.weekly"),
        ])
        descriptor.pinnable = false
        XCTAssertEqual(titles(DashboardMenus.metric(descriptor, isStarred: false)), [["Hide"]])
    }
}

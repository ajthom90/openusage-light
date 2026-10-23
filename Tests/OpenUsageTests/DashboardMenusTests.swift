import XCTest
@testable import OpenUsage

/// Apart from the ↺ tag's resets popover, right-click is the only way to act on the dashboard.
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
            .open(URL(string: "https://status.claude.com/")!),
            .open(URL(string: "https://claude.ai/settings/usage")!),
        ])
    }

    func testThePlainAccountMenu() {
        let menu = DashboardMenus.account(account(), status: nil, canShare: true, hasHiddenMetrics: false)
        XCTAssertEqual(titles(menu), [["Refresh", "Rename", "Edit Account…"], ["Share Screenshot"]])
        XCTAssertEqual(menu.flatMap { $0 }.map(\.command), [
            .refresh(["claude@1"]), .rename("claude@1"), .editAccount("claude@1"), .shareScreenshot("claude@1"),
        ])
    }

    /// The menu says why the account line shows a warning and that metrics are hidden. Resets live in
    /// the ↺ tag's popover, so the menu has no reset item even when the account has resets.
    func testTheAccountMenuExplainsItsStatusAndShowsHiddenMetrics() {
        let menu = DashboardMenus.account(
            account(resetExpiries: [now.addingTimeInterval(6 * 86_400)]),
            status: "Couldn't refresh. Check your connection.",
            canShare: true,
            hasHiddenMetrics: true
        )

        XCTAssertEqual(titles(menu), [
            ["Couldn't refresh. Check your connection."],
            ["Refresh", "Rename", "Edit Account…"],
            ["Share Screenshot"],
            ["Show Hidden Metrics"],
        ])
        XCTAssertNil(menu[0][0].command, "the status is a disabled line")
        XCTAssertEqual(menu[3][0].command, .showHiddenMetrics("claude@1"))
    }

    /// A card with one account has no account line, so its menu carries the account's commands and the
    /// provider's, with one Refresh.
    func testAOneAccountCardsMenuMergesTheAccountAndProviderMenus() {
        let menu = DashboardMenus.soleAccount(
            account(),
            status: "Couldn't refresh. Check your connection.",
            canShare: true,
            hasHiddenMetrics: true
        )

        XCTAssertEqual(titles(menu), [
            ["Couldn't refresh. Check your connection."],
            ["Refresh"],
            ["Rename", "Edit Account…", "Manage Accounts…"],
            ["Share Screenshot"],
            ["Show Hidden Metrics"],
            ["Status Page", "Usage Dashboard"],
        ])
        XCTAssertEqual(menu.flatMap { $0 }.map(\.command), [
            nil,
            .refresh(["claude@1"]),
            .rename("claude@1"), .editAccount("claude@1"), .manageAccounts,
            .shareScreenshot("claude@1"),
            .showHiddenMetrics("claude@1"),
            .open(URL(string: "https://status.claude.com/")!), .open(URL(string: "https://claude.ai/settings/usage")!),
        ])
        XCTAssertEqual(
            titles(DashboardMenus.soleAccount(account(), status: nil, canShare: true, hasHiddenMetrics: false)),
            [["Refresh"], ["Rename", "Edit Account…", "Manage Accounts…"], ["Share Screenshot"], ["Status Page", "Usage Dashboard"]]
        )
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

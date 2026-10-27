import XCTest
@testable import OpenUsage

/// Apart from the Limit Resets row's popover, right-click is the only way to act on the dashboard, and
/// its Share Screenshot the only way to copy a picture: a provider's header shares all its accounts, an
/// account's caption that account.
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
        var lines: [DashboardLine] = []
        if let resetExpiries {
            var data = WidgetData(title: "Limit Resets", icon: .providerMark("claude"), kind: .count, used: 2, limit: nil)
            data.values = [MetricValue(number: 2, kind: .count, label: "available")]
            data.showsResetExpiries = true
            data.expiriesAt = resetExpiries
            lines = [DashboardLine(descriptor: WidgetDescriptor(id: "resets", providerID: "claude", metricLabel: data.title, sample: data), data: data)]
        }
        return DashboardAccount(provider: claude, lines: lines)
    }

    func testTheProviderMenuRefreshesManagesSharesEveryAccountAndOpensTheLinks() {
        let sole = DashboardMenus.provider(DashboardFamily(id: "claude", provider: claude, accounts: [account()]))
        XCTAssertEqual(titles(sole), [["Refresh"], ["Manage Accounts…"], ["Share Screenshot"], ["Status Page", "Usage Dashboard"]],
                       "a one-account card's header has the provider's menu too")
        XCTAssertEqual(sole[2][0].command, .shareScreenshot(["claude@1"]))

        let other = Provider(id: "claude@2", displayName: "Claude", icon: .providerMark("claude"), accountLabel: "AM 1")
        let family = DashboardFamily(id: "claude", provider: claude, accounts: [account(), DashboardAccount(provider: other, lines: [])])
        let menu = DashboardMenus.provider(family)

        XCTAssertEqual(titles(menu), [["Refresh"], ["Manage Accounts…"], ["Share Screenshot"], ["Status Page", "Usage Dashboard"]])
        XCTAssertEqual(menu[0][0].command, .refresh(["claude@1", "claude@2"]))
        XCTAssertEqual(menu[2][0].command, .shareScreenshot(["claude@1", "claude@2"]), "the header shares the whole card")
        XCTAssertEqual(menu[3].map(\.command), [
            .open(URL(string: "https://status.claude.com/")!),
            .open(URL(string: "https://claude.ai/settings/usage")!),
        ])
    }

    func testThePlainAccountMenu() {
        let menu = DashboardMenus.account(account(), status: nil, hasHiddenMetrics: false)
        XCTAssertEqual(titles(menu), [["Refresh", "Rename", "Edit Account…"], ["Share Screenshot"]])
        XCTAssertEqual(menu.flatMap { $0 }.map(\.command), [
            .refresh(["claude@1"]), .rename("claude@1"), .editAccount("claude@1"), .shareScreenshot(["claude@1"]),
        ])
    }

    /// The menu says why the caption shows a warning and that metrics are hidden. Resets live in the
    /// Limit Resets row's popover, so the menu has no reset item even when the account has resets.
    func testTheAccountMenuExplainsItsStatusAndShowsHiddenMetrics() {
        let menu = DashboardMenus.account(
            account(resetExpiries: [now.addingTimeInterval(6 * 86_400)]),
            status: "Couldn't refresh. Check your connection.",
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

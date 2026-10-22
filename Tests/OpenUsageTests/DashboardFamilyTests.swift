import XCTest
@testable import OpenUsage

final class DashboardFamilyTests: XCTestCase {
    func testEveryMetricWithDataIsALineAndAccountsShareTheirProviderCard() {
        func provider(_ id: String) -> Provider {
            Provider(id: id, displayName: "Claude", icon: .providerMark("claude"), accountLabel: id)
        }
        func data(_ title: String, hasData: Bool = true) -> WidgetData {
            var data = WidgetData(title: title, icon: .providerMark("claude"), kind: .percent, used: 10, limit: 100)
            data.hasData = hasData
            return data
        }
        let samples = ["session": data("Session"), "fable": data("Fable"), "weekly": data("Weekly", hasData: false)]
        let groups = [
            ProviderGroup(provider: provider("claude@1"), widgets: ["session", "fable", "weekly"].map { PlacedWidget(descriptorID: $0) }),
            ProviderGroup(provider: provider("claude@2"), widgets: [PlacedWidget(descriptorID: "fable")]),
        ]
        let families = DashboardFamily.make(groups: groups) { widget in
            samples[widget.descriptorID].map {
                DashboardLine(descriptor: WidgetDescriptor(id: widget.descriptorID, providerID: "claude", metricLabel: $0.title, sample: $0), data: $0)
            }
        }
        XCTAssertEqual(families.map(\.id), ["claude"])
        XCTAssertEqual(families[0].accounts.map { $0.lines.map(\.id) }, [["session", "fable"], ["fable"]])
    }

    func testCollapsedAccountShowsItsFirstTwoLimitedMetricsInTheUsersOrder() {
        func line(_ id: String, limit: Double?) -> DashboardLine {
            var data = WidgetData(title: id, icon: .providerMark("codex"), kind: limit == nil ? .count : .percent, used: 5, limit: limit)
            if limit == nil { data.values = [MetricValue(number: 5, kind: .count, label: "available")] }
            return DashboardLine(descriptor: WidgetDescriptor(id: id, providerID: "codex", metricLabel: id, sample: data), data: data)
        }
        func account(_ lines: [DashboardLine]) -> DashboardAccount {
            DashboardAccount(provider: Provider(id: "codex@1", displayName: "Codex", icon: .providerMark("codex")), lines: lines)
        }
        // A Codex account whose only limit is weekly keeps that bar, ahead of its readings without a limit.
        let codex = account([line("Weekly", limit: 100), line("Resets", limit: nil), line("Credits", limit: nil)])
        XCTAssertEqual(codex.summaryLines.map(\.id), ["Weekly"])
        XCTAssertTrue(codex.isExpandable(plan: nil))
        // The user's order decides which two show; a third limit waits for the expanded account.
        let claude = account([line("Fable", limit: 100), line("Resets", limit: nil), line("Session", limit: 100), line("Weekly", limit: 100)])
        XCTAssertEqual(claude.summaryLines.map(\.id), ["Fable", "Session"])
        // Without any limit the first reading stands in, so a collapsed account is never just a name.
        let balance = account([line("Credits", limit: nil), line("Resets", limit: nil)])
        XCTAssertEqual(balance.summaryLines.map(\.id), ["Credits"])
        // Expanding has to reveal something: another line or the plan.
        let single = account([line("Session", limit: 100)])
        XCTAssertFalse(single.isExpandable(plan: nil))
        XCTAssertTrue(single.isExpandable(plan: "Pro"))
    }

    func testResetsAreALineInTheUsersOrderOnlyWhileOneIsAvailable() {
        func resets(_ count: Double) -> WidgetData {
            var data = WidgetData(title: "Rate Limit Resets", icon: .providerMark("codex"), kind: .count, used: count, limit: nil)
            data.values = [MetricValue(number: count, kind: .count, label: "available")]
            data.showsResetExpiries = true
            return data
        }
        let weekly = WidgetData(title: "Weekly", icon: .providerMark("codex"), kind: .percent, used: 10, limit: 100)
        func lines(resetCount: Double) -> [String] {
            let samples = ["resets": resets(resetCount), "weekly": weekly]
            let group = ProviderGroup(
                provider: Provider(id: "codex@1", displayName: "Codex", icon: .providerMark("codex")),
                widgets: ["resets", "weekly"].map { PlacedWidget(descriptorID: $0) }
            )
            return DashboardFamily.make(groups: [group]) { widget in
                samples[widget.descriptorID].map {
                    DashboardLine(descriptor: WidgetDescriptor(id: widget.descriptorID, providerID: "codex", metricLabel: $0.title, sample: $0), data: $0)
                }
            }[0].accounts[0].lines.map(\.id)
        }
        XCTAssertEqual(lines(resetCount: 2), ["resets", "weekly"])
        XCTAssertEqual(lines(resetCount: 0), ["weekly"])
    }

    func testResetsLineCountsDownToTheSoonestExpiry() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var data = WidgetData(title: "Rate Limit Resets", icon: .providerMark("codex"), kind: .count, used: 2, limit: nil)
        data.values = [MetricValue(number: 2, kind: .count, label: "available")]
        data.showsResetExpiries = true
        data.expiriesAt = [now.addingTimeInterval(15 * 86_400), now.addingTimeInterval(6 * 86_400 + 3 * 3_600)]
        XCTAssertEqual(data.dashboardTitle, "Resets")
        XCTAssertEqual(data.unboundedDetail, "2 available")
        XCTAssertEqual(data.compactResetText(now: now), "6d 3h")
        XCTAssertEqual(data.expirySeverity(now: now), .warning)
    }
}

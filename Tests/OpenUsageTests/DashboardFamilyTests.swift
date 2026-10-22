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

    func testResetsRideOnTheAccountOnlyWhileOneIsAvailable() {
        func resets(_ count: Double) -> WidgetData {
            var data = WidgetData(title: "Rate Limit Resets", icon: .providerMark("codex"), kind: .count, used: count, limit: nil)
            data.values = [MetricValue(number: count, kind: .count, label: "available")]
            data.showsResetExpiries = true
            return data
        }
        let weekly = WidgetData(title: "Weekly", icon: .providerMark("codex"), kind: .percent, used: 10, limit: 100)
        func account(resetCount: Double) -> DashboardAccount {
            let samples = ["resets": resets(resetCount), "weekly": weekly]
            let group = ProviderGroup(
                provider: Provider(id: "codex@1", displayName: "Codex", icon: .providerMark("codex")),
                widgets: ["resets", "weekly"].map { PlacedWidget(descriptorID: $0) }
            )
            return DashboardFamily.make(groups: [group]) { widget in
                samples[widget.descriptorID].map {
                    DashboardLine(descriptor: WidgetDescriptor(id: widget.descriptorID, providerID: "codex", metricLabel: $0.title, sample: $0), data: $0)
                }
            }[0].accounts[0]
        }
        XCTAssertEqual(account(resetCount: 2).lines.map(\.id), ["weekly"])
        XCTAssertEqual(account(resetCount: 2).resets?.resetCreditCount, 2)
        XCTAssertEqual(account(resetCount: 0).lines.map(\.id), ["weekly"])
        XCTAssertNil(account(resetCount: 0).resets)
    }
}

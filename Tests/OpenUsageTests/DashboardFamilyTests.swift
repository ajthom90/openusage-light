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

    func testTheHeaderNamesASoleAccountAndTheImageLeavesItsEmailOut() {
        func family(_ accounts: [Provider]) -> DashboardFamily {
            DashboardFamily(id: "codex", provider: accounts[0], accounts: accounts.map { DashboardAccount(provider: $0, lines: []) })
        }
        func codex(_ label: String?) -> Provider {
            Provider(id: "codex@\(label ?? "plain")", displayName: "Codex", icon: .providerMark("codex"), accountLabel: label)
        }
        // One account: "Provider — name", its email when it has no name of its own, and the provider
        // alone when it is named like its provider.
        XCTAssertEqual(family([codex("Sunstory")]).headerTitle, "Codex — Sunstory")
        XCTAssertEqual(family([codex("sam@hey.com")]).headerTitle, "Codex — sam@hey.com")
        XCTAssertEqual(family([codex("Codex")]).headerTitle, "Codex")
        XCTAssertEqual(family([codex(nil)]).headerTitle, "Codex")
        // Several accounts: the provider alone; each account's name goes on its caption.
        XCTAssertEqual(family([codex("Sunstory"), codex("sam@hey.com")]).headerTitle, "Codex")
        XCTAssertEqual(family([codex("Sunstory"), codex("sam@hey.com")]).accounts.map(\.name), ["Sunstory", "sam@hey.com"])
        // The copied image keeps a custom name and drops an email, in the header and on captions.
        XCTAssertEqual(family([codex("Sunstory")]).hidingEmails.headerTitle, "Codex — Sunstory")
        XCTAssertEqual(family([codex("sam@hey.com")]).hidingEmails.headerTitle, "Codex")
        XCTAssertEqual(family([codex("Sunstory"), codex("sam@hey.com")]).hidingEmails.accounts.map(\.name), ["Sunstory", "Codex"])
    }

    func testTheLimitResetsRowShowsOnlyWhileAResetIsAvailable() {
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
        XCTAssertEqual(account(resetCount: 2).lines.map(\.id), ["resets", "weekly"])
        XCTAssertEqual(account(resetCount: 0).lines.map(\.id), ["weekly"])
    }
}

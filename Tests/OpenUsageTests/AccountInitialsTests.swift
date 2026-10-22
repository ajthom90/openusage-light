import XCTest
@testable import OpenUsage

final class AccountInitialsTests: XCTestCase {
    func testInitialsFollowAvatarFallback() {
        XCTAssertEqual(AccountInitials.make("Personal"), "P")
        XCTAssertEqual(AccountInitials.make("AM 1"), "A1")
        XCTAssertEqual(AccountInitials.make("AM2"), "A2")
        XCTAssertEqual(AccountInitials.make("Side Project"), "SP")
        XCTAssertEqual(AccountInitials.make("rob@sunstory.com"), "R")
        XCTAssertEqual(AccountInitials.make("first.last@example.com"), "FL")
        XCTAssertEqual(AccountInitials.make("  "), "")
    }

    func testCollidingInitialsFallBackToFirstTwoLetters() {
        XCTAssertEqual(AccountInitials.tags(for: ["Work", "Web", "Personal"]), ["WO", "WE", "P"])
    }

    @MainActor
    func testStripBadgesOnlyProvidersWithSeveralAccounts() {
        func group(_ id: String, _ label: String) -> ProviderMetrics {
            let provider = Provider(id: id, displayName: "P", icon: .providerMark("claude"), accountLabel: label)
            let sample = WidgetData(title: "Session", icon: provider.icon, kind: .percent, used: 10, limit: 100)
            let descriptor = WidgetDescriptor(id: "\(id).session", providerID: id, metricLabel: "Session", sample: sample)
            return ProviderMetrics(provider: provider, metrics: [descriptor])
        }
        let content = MenuBarContentBuilder.build(
            groups: [group("claude@1", "Personal"), group("claude@2", "AM 1"), group("codex@1", "rob@sunstory.com")],
            data: { $0.sample }
        )
        XCTAssertEqual(content.groups.map(\.badge), ["P", "A1", nil])
    }
}

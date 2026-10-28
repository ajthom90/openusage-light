import XCTest
import OpenUsageCore
@testable import OpenUsage

final class ICloudPublisherTests: XCTestCase {
    private func entry(_ kind: ProviderKind, label: String) -> LimitsProjection.Entry {
        let account = Account(kind: kind, label: label)
        let snapshot = ProviderSnapshot(
            providerID: account.cardID, displayName: kind.displayName, plan: "Pro",
            lines: [.progress(label: "Session", used: 40, limit: 100, format: .percent, resetsAt: nil, periodDurationMs: nil)],
            refreshedAt: Date()
        )
        return LimitsProjection.Entry(account: account, snapshot: snapshot, descriptors: [])
    }

    @MainActor
    func testDocumentFollowsTheSavedOrderAndCarriesNoCredentials() throws {
        let claude = entry(.claude, label: "Work"), codex = entry(.codex, label: "Personal")
        let data = try ICloudPublisher.document(
            entries: [claude, codex], savedOrder: [codex.account.cardID, claude.account.cardID], now: Date()
        )
        let envelope = try LimitsEnvelope.decode(data)
        XCTAssertEqual(envelope.order, [codex.account.cardID, claude.account.cardID])
        let text = String(decoding: data, as: UTF8.self).lowercased()
        for forbidden in ["token", "apikey", "api_key", "secret", "password"] {
            XCTAssertFalse(text.contains(forbidden), "document mentions \(forbidden)")
        }
    }

    @MainActor
    func testPublisherIsOffWithoutAContainerEvenWhenSwitchedOn() {
        let defaults = UserDefaults(suiteName: "icloud-test-\(UUID())")!
        defaults.set(true, forKey: ICloudPublisher.enabledKey)
        XCTAssertFalse(ICloudPublisher(containerIdentifier: nil, defaults: defaults).isEnabled)
    }
}

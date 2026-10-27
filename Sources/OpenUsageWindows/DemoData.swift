#if os(Windows)
import Foundation
import OpenUsageCore

/// Sample accounts and snapshots for `--demo`, so the popover can be drawn and checked without signing
/// in to anything. Nothing here touches the network or the real data folder.
enum DemoData {
    @MainActor
    static func makeModel() -> DashboardModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpenUsageLightDemo-\(UUID().uuidString)")
        let settings = FileSettingsStore(directory: directory)
        let accounts = AccountStore(defaults: settings, vault: InMemoryCredentialVault())
        let cache = ProviderSnapshotCache(userDefaults: settings)
        let now = Date()

        func add(_ kind: ProviderKind, _ label: String, plan: String?, warning: String? = nil, lines: [MetricLine]) {
            let account = accounts.add(kind: kind, label: label, credential: .apiKey("demo"))
            cache.store(ProviderSnapshot(
                providerID: account.cardID, displayName: kind.displayName, plan: plan, lines: lines, refreshedAt: now, warning: warning
            ))
        }
        func percent(_ label: String, _ used: Double, hours: Double, window: Int) -> MetricLine {
            .progress(label: label, used: used, limit: 100, format: .percent,
                      resetsAt: now.addingTimeInterval(hours * 3600), periodDurationMs: window * 3_600_000)
        }

        add(.claude, "Work", plan: "Max 20x", lines: [
            percent("Session", 36, hours: 2.8, window: 5),
            percent("Weekly", 68, hours: 96, window: 168),
            percent("Sonnet", 12, hours: 96, window: 168)
        ])
        add(.codex, "Personal", plan: "Pro 100", lines: [
            percent("Session", 94, hours: 1.2, window: 5),
            percent("Weekly", 41, hours: 120, window: 168)
        ])
        add(.cursor, "Team", plan: "Pro", warning: "Re-login for live usage", lines: [
            percent("Total usage", 55, hours: 240, window: 720)
        ])
        add(.openrouter, "OpenRouter", plan: "Free", lines: [
            .values(label: "Balance", values: [MetricValue(number: 12.4, kind: .dollars)]),
            .values(label: "Today", values: [MetricValue(number: 0.35, kind: .dollars)])
        ])
        return DashboardModel(accounts: accounts, settings: settings)
    }
}
#endif

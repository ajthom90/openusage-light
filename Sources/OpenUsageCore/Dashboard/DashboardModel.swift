import Foundation

/// One account's card as a surface draws it: who it is, and the rows that have data.
package struct DashboardSection: Equatable, Identifiable, Sendable {
    package let id: String
    /// The provider's name ("Claude").
    package let provider: String
    /// The account's name as the user set it.
    package let account: String
    package let plan: String?
    /// A current refresh failure, or the snapshot's soft warning when it has none.
    package let notice: String?
    /// `true` once the snapshot has missed more than one refresh.
    package let outdated: Bool
    package let rows: [DashboardRowModel]

    package init(
        id: String, provider: String, account: String, plan: String?, notice: String?, outdated: Bool,
        rows: [DashboardRowModel]
    ) {
        self.id = id
        self.provider = provider
        self.account = account
        self.plan = plan
        self.notice = notice
        self.outdated = outdated
        self.rows = rows
    }
}

/// The dashboard's state, independent of any window system: the accounts in the user's order, their
/// latest snapshots, and the rows each draws. A surface calls `reload()` when accounts change and
/// `refresh()` on its timer, and redraws from `sections` when `onChange` fires.
@MainActor
package final class DashboardModel {
    package private(set) var sections: [DashboardSection] = []
    package private(set) var isRefreshing = false
    package private(set) var lastRefreshed: Date?
    /// Called after `sections` or `isRefreshing` changes.
    package var onChange: (() -> Void)?

    package let accounts: AccountStore
    private let settings: any SettingsStore
    private let cache: ProviderSnapshotCache
    private let http: any HTTPClient
    private let now: () -> Date
    private var runtimes: [AccountProviderRuntime] = []
    private var failures: [String: String] = [:]

    package init(
        accounts: AccountStore,
        settings: any SettingsStore,
        http: any HTTPClient = URLSessionHTTPClient(),
        now: @escaping () -> Date = Date.init
    ) {
        self.accounts = accounts
        self.settings = settings
        self.cache = ProviderSnapshotCache(userDefaults: settings)
        self.http = http
        self.now = now
        reload()
    }

    /// Rebuilds the runtimes from the account list and redraws from the cached snapshots.
    package func reload() {
        let existing = Dictionary(runtimes.map { ($0.account.id, $0) }, uniquingKeysWith: { first, _ in first })
        runtimes = Self.ordered(accounts.accounts, by: SavedDashboardOrder.providerOrder(in: settings)).map { account in
            if let runtime = existing[account.id] {
                runtime.update(account)
                return runtime
            }
            return AccountProviderRuntime(account: account, vault: accounts.credentialVault, http: http, now: now)
        }
        failures = failures.filter { id, _ in runtimes.contains { $0.provider.id == id } }
        rebuild()
    }

    /// Refreshes every account (all at once) and redraws.
    package func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        onChange?()
        let refresher = SnapshotRefresher(cache: cache, now: now)
        let tasks = runtimes.map { runtime in Task { @MainActor in await refresher.fetch(runtime, force: force) } }
        for (runtime, task) in zip(runtimes, tasks) {
            let result = await task.value
            failures[runtime.provider.id] = result.failure?.message
        }
        isRefreshing = false
        lastRefreshed = now()
        rebuild()
    }

    private func rebuild() {
        let snapshots = cache.loadSnapshots(providerIDs: runtimes.map(\.provider.id))
        let at = now()
        sections = runtimes.map { runtime in
            let snapshot = snapshots[runtime.provider.id]
            let rows = runtime.widgetDescriptors.compactMap { descriptor -> DashboardRowModel? in
                let data = WidgetResolver.data(
                    for: descriptor, snapshot: snapshot, displayMode: .remaining, resetDisplayMode: .relative
                )
                return data.hasData ? data.dashboardRow(now: at) : nil
            }
            let age = snapshot.map { at.timeIntervalSince($0.refreshedAt) }
            return DashboardSection(
                id: runtime.provider.id,
                provider: runtime.account.kind.displayName,
                account: runtime.account.label,
                plan: snapshot?.plan,
                notice: failures[runtime.provider.id] ?? snapshot?.warning,
                outdated: (age ?? 0) >= RefreshSetting.interval * 2,
                rows: rows
            )
        }
        onChange?()
    }

    private static func ordered(_ accounts: [Account], by saved: [String]) -> [Account] {
        let position = Dictionary(saved.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let known = accounts.filter { position[$0.cardID] != nil }.sorted { position[$0.cardID]! < position[$1.cardID]! }
        return known + accounts.filter { position[$0.cardID] == nil }
    }
}

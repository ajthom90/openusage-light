import Foundation
import Observation

/// Owns the app's long-lived stores. Accounts are the source of truth: when they change, the container
/// updates the runtimes, layout, and data store in place, so the status item, panel, and every other
/// account's data stay as they are.
@MainActor
@Observable
final class AppContainer {
    let accounts: AccountStore
    let notificationSettings: NotificationSettingsStore
    let layout: LayoutStore
    let dataStore: WidgetDataStore
    let transparency: PopoverTransparencyStore
    let renaming: AccountRenameStore
    @ObservationIgnored private var providers: [AccountProviderRuntime]
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(accounts: AccountStore = AccountStore(), defaults: UserDefaults = .standard) async {
        self.accounts = accounts
        let providers = ProviderCatalog.make(accounts: accounts.accounts, vault: accounts.credentialVault)
        let registry = WidgetRegistry.from(providers)
        let notificationSettings = NotificationSettingsStore(defaults: defaults)
        let layout = LayoutStore(registry: registry, defaults: defaults)
        let dataStore = WidgetDataStore(
            registry: registry,
            providers: providers,
            cache: ProviderSnapshotCache(userDefaults: defaults),
            defaults: defaults,
            orderedDescriptors: { [layout] in layout.visiblePlaced.compactMap { layout.descriptor(for: $0) } },
            notificationSettings: { notificationSettings }
        )
        self.providers = providers
        self.notificationSettings = notificationSettings
        self.layout = layout
        self.dataStore = dataStore
        self.transparency = PopoverTransparencyStore()
        self.renaming = AccountRenameStore(accounts: accounts)
        AppNotifications.shared.registerAsDelegate()
        observeAccounts()
    }

    deinit {
        refreshTask?.cancel()
    }

    /// The resets popover's claim seam for one account card, or `nil` when the account has no reset claims.
    /// A claim that changed anything refreshes that account, so its meters and reset count catch up.
    func resetClaim(for providerID: String) -> ResetClaimService? {
        guard let runtime = providers.first(where: { $0.provider.id == providerID }) else { return nil }
        return runtime.resetClaimService { [dataStore] in
            await dataStore.refresh(providerID: providerID, force: true)
        }
    }

    func startRefreshing() {
        guard refreshTask == nil else { return }
        refreshTask = Task {
            while !Task.isCancelled {
                await dataStore.refreshAll()
                await dataStore.evaluateNotifications()
                try? await Task.sleep(for: .milliseconds(Int64(RefreshSetting.interval * 1_000)))
            }
        }
    }

    private func observeAccounts() {
        withObservationTracking {
            _ = accounts.accounts
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.syncAccounts()
                self?.observeAccounts()
            }
        }
    }

    private func syncAccounts() {
        let previousIDs = Set(providers.map(\.provider.id))
        providers = ProviderCatalog.make(
            accounts: accounts.accounts,
            vault: accounts.credentialVault,
            reusing: providers
        )
        let registry = WidgetRegistry.from(providers)
        layout.apply(registry: registry)
        dataStore.apply(providers: providers, registry: registry)
        for id in providers.map(\.provider.id) where !previousIDs.contains(id) {
            Task { await dataStore.refresh(providerID: id, force: true) }
        }
    }
}

import Foundation

@MainActor
@Observable
final class AppContainer {
    let accounts: AccountStore
    let providers: [ProviderRuntime]
    let registry: WidgetRegistry
    let notificationSettings: NotificationSettingsStore
    let layout: LayoutStore
    let dataStore: WidgetDataStore
    let transparency: PopoverTransparencyStore
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    var onAccountsChanged: (@MainActor () -> Void)?

    init(accounts: AccountStore = AccountStore()) async {
        self.accounts = accounts
        let providers = ProviderCatalog.make(accounts: accounts.accounts, vault: accounts.credentialVault)
        let registry = WidgetRegistry.from(providers)
        let notificationSettings = NotificationSettingsStore()
        let accountDefaults: ([String]) -> [String] = { metricIDs in
            DefaultLayout.expandingAccounts(metricIDs, providerIDs: registry.providers.map(\.id))
        }
        let layout = LayoutStore(
            registry: registry,
            defaultMetricIDs: accountDefaults(DefaultLayout.metricIDs),
            defaultPinnedMetricIDs: accountDefaults(DefaultLayout.pinnedMetricIDs),
            defaultExpandedMetricIDs: accountDefaults(DefaultLayout.expandedMetricIDs)
        )
        let dataStore = WidgetDataStore(
            registry: registry,
            providers: providers,
            orderedDescriptors: { [layout] in layout.visiblePlaced.compactMap { layout.descriptor(for: $0) } },
            notificationSettings: { notificationSettings }
        )
        self.providers = providers
        self.registry = registry
        self.notificationSettings = notificationSettings
        self.layout = layout
        self.dataStore = dataStore
        self.transparency = PopoverTransparencyStore()
        AppNotifications.shared.registerAsDelegate()
    }

    func rebuildAfterAccountChange() {
        onAccountsChanged?()
    }

    deinit {
        refreshTask?.cancel()
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
}

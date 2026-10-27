import XCTest
@testable import OpenUsage
@testable import OpenUsageCore

/// A provider whose rows are missing from the default layout signs in to a dashboard with every meter
/// switched off. This fails first when a new provider forgets to add its rows.
@MainActor
final class DefaultLayoutCoverageTests: XCTestCase {
    func testEveryProvidersRowsAreOnByDefault() {
        for kind in ProviderKind.allCases {
            let runtime = AccountProviderRuntime(account: Account(kind: kind, label: "Work"), vault: InMemoryCredentialVault())
            let prefix = runtime.provider.id.count
            for descriptor in runtime.widgetDescriptors {
                let id = "\(kind.rawValue)\(descriptor.id.dropFirst(prefix))"
                XCTAssertTrue(DefaultLayout.metricIDs.contains(id), "\(id) is not in the default layout")
            }
        }
    }

    func testANewMuseCodeAccountShowsSessionAndWeeklyAndPinsThem() {
        let name = "OpenUsageTests.DefaultCoverage.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let accounts = AccountStore(defaults: defaults, vault: InMemoryCredentialVault())
        let layout = LayoutStore(
            registry: WidgetRegistry.from(ProviderCatalog.make(accounts: [], vault: accounts.credentialVault)), defaults: defaults
        )

        let account = accounts.add(kind: .musecode, label: "Muse Code", credential: .oauth(OAuthTokens(accessToken: "t")))
        layout.apply(registry: WidgetRegistry.from(ProviderCatalog.make(accounts: accounts.accounts, vault: accounts.credentialVault)))

        let shown = Set(layout.placed.map(\.descriptorID))
        XCTAssertTrue(shown.contains("\(account.cardID).session"), "\(shown)")
        XCTAssertTrue(shown.contains("\(account.cardID).weekly"), "\(shown)")
    }
}

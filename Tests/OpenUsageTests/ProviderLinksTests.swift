import XCTest
@testable import OpenUsage

final class ProviderLinksTests: XCTestCase {
    @MainActor
    func testAccountProvidersCarryTheirQuickLinks() {
        let runtime = AccountProviderRuntime(account: Account(kind: .claude, label: "AM 1"), vault: InMemoryCredentialVault())
        XCTAssertEqual(runtime.provider.visibleLinks.map(\.label), ["Status Page", "Usage Dashboard"])
    }

    func testEveryLinkIsAnHTTPSURL() {
        for kind in ProviderKind.allCases {
            for link in kind.links {
                XCTAssertEqual(URL(string: link.url)?.scheme, "https", "\(kind) \(link.label)")
            }
        }
    }
}

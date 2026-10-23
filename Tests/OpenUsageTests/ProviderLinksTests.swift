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

    /// Every API-key provider's sheet links to the page where the key is created, on its own site.
    func testEveryAPIKeyProviderLinksToItsKeyPage() {
        let keyPages = ProviderKind.allCases.compactMap { kind -> (ProviderKind, URL)? in
            guard case .apiKey(let keyPage) = kind.authMethod else { return nil }
            return (kind, keyPage)
        }
        XCTAssertEqual(keyPages.map(\.0), [.ollama, .opencodeGo, .openrouter, .zai])
        XCTAssertEqual(keyPages.map(\.1.absoluteString), [
            "https://ollama.com/settings/keys",
            "https://opencode.ai/console",
            "https://openrouter.ai/settings/management-keys",
            "https://z.ai/manage-apikey/apikey-list",
        ])
    }

    /// opencode.ai/auth became OpenCode's OAuth authorize page, which shows an error when opened
    /// directly; the Go docs send subscribers to the Console for their usage.
    func testOpenCodeUsageDashboardIsTheConsole() {
        XCTAssertEqual(ProviderKind.opencodeGo.links.map(\.url), ["https://opencode.ai/console"])
    }
}

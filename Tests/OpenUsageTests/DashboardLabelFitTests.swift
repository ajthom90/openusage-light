import AppKit
import SwiftUI
import XCTest
@testable import OpenUsage

/// Every metric title, plan and name a provider can produce renders at full size in the panel: every
/// title fits the 86 pt label column, no plan truncates, and Robin's own accounts fit their headers and
/// captions whole. Plans are the providers' official names, never shortened to fit; a long account name
/// moves to its caption instead.
@MainActor
final class DashboardLabelFitTests: XCTestCase {
    /// A provider's card: the panel minus its margin on each side.
    private let cardWidth = PanelMetrics.width - 2 * PanelMetrics.margin

    /// Every provider's titles fit the fixed label column at the row's type size, so no label truncates.
    func testEveryProvidersMetricTitlesFitTheLabelColumn() {
        for kind in ProviderKind.allCases {
            let runtime = AccountProviderRuntime(account: Account(kind: kind, label: kind.displayName), vault: InMemoryCredentialVault())
            for title in runtime.widgetDescriptors.map(\.sample.title) {
                XCTAssertLessThanOrEqual(idealWidth(Text(title).font(DashboardMetricRow.font)), DashboardGrid.labelWidth, "\(kind.displayName): \(title)")
            }
        }
    }

    /// Two metrics of one account never share a title, so no two rows read the same.
    func testEveryProvidersMetricTitlesAreDistinct() {
        for kind in ProviderKind.allCases {
            let runtime = AccountProviderRuntime(account: Account(kind: kind, label: kind.displayName), vault: InMemoryCredentialVault())
            let titles = runtime.widgetDescriptors.map(\.sample.title)
            XCTAssertEqual(Set(titles).count, titles.count, "\(kind.displayName): \(titles)")
        }
        let antigravity = AccountProviderRuntime(account: Account(kind: .antigravity, label: "Antigravity"), vault: InMemoryCredentialVault())
        XCTAssertEqual(antigravity.widgetDescriptors.map(\.sample.title), ["Gemini 5h", "Gemini", "Argon", "Claude 5h", "Claude"])
    }

    /// Each plan a mapper can name fits in its header beside the provider's own name, which is what an
    /// account nobody renamed is called.
    func testEveryPlanFitsInItsHeader() throws {
        for (kind, plans) in try plansByProvider() {
            XCTAssertFalse(plans.isEmpty, kind.displayName)
            for plan in plans {
                XCTAssertLessThanOrEqual(idealWidth(header(kind: kind, name: kind.displayName, plan: plan)), cardWidth, "\(kind.displayName): \(plan)")
            }
        }
    }

    /// Robin's accounts, names and plans, as the dashboard draws them: a one-account provider in its
    /// header when that fits — `DashboardHeaderLine.fits`, checked against what the header really asks
    /// for when it names the account — on its caption otherwise, and a provider with several accounts
    /// on each account's caption. "Grok — Grok Account  SuperGrok Heavy" asks for 301 of the 316 pt
    /// and still moves: the 15 pt left is less than the refresh spinner's room, and the name must
    /// never be cut while the spinner shows.
    func testRobinsAccountsFitWithoutTruncating() {
        let soleAccounts: [(ProviderKind, String, String, inHeader: Bool)] = [
            (.codex, "Sunstory", "Pro 200", true), (.opencodeGo, "Go Basic", "Go", true),
            (.grok, "Grok Account", "SuperGrok Heavy", false), (.grok, "rob@sunstory.com", "SuperGrok Heavy", false),
            (.cursor, "rob@sunstory.com", "Ultra", true), (.copilot, "robinebers", "Individual", true),
            (.codex, "sam@hey.com", "Plus", true),
        ]
        for (kind, name, plan, inHeader) in soleAccounts {
            let provider = account(kind, name).provider
            let fits = DashboardHeaderLine.fits(provider: provider, name: name, plan: plan, width: cardWidth)
            XCTAssertEqual(fits, inHeader, "\(kind.displayName) — \(name)  \(plan)")
            let asked = idealWidth(header(kind: kind, name: name, plan: plan, naming: true))
            if fits {
                XCTAssertLessThanOrEqual(asked, cardWidth, "\(name) is named in the header and truncates there")
            } else {
                XCTAssertGreaterThan(asked, cardWidth - 40, "\(name) moves to the caption with room to spare in the header")
            }
        }
        let captions: [(ProviderKind, String, String)] = [
            (.claude, "Personal", "Max 20x"), (.claude, "Attention Machine 1", "Team 5x"),
            (.claude, "Attention Machine 2", "Team 5x"),
        ]
        for (kind, name, plan) in captions {
            let caption = DashboardAccountCaption(account: account(kind, name), plan: plan)
            XCTAssertLessThanOrEqual(idealWidth(caption), cardWidth - 2 * DashboardGrid.cardPadding, name)
        }
    }

    /// The hover text keeps cents, but a whole-dollar value drops them.
    func testWholeDollarValuesDropTheirCents() {
        XCTAssertEqual(meter(left: 500, limit: 500).valueText, "$500")
        XCTAssertEqual(meter(left: 37.42, limit: 100).valueText, "$37.42")
        XCTAssertEqual(meter(left: 2.5, limit: 2.5).valueText, "$2.50")
        XCTAssertEqual(meter(left: 0.004, limit: 100).valueText, "$0")
        XCTAssertEqual(meter(left: 1_234, limit: 2_000).valueText, "$1.2K")
    }

    // MARK: - Helpers

    private func plansByProvider() throws -> [(ProviderKind, [String])] {
        func json(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
        let claude = ["pro", "max", "team", "enterprise"].flatMap { type in
            [nil, "default_claude_max_5x", "default_claude_max_20x"].compactMap {
                ClaudeUsageMapper.formatPlan(subscriptionType: type, rateLimitTier: $0)
            }
        }
        let codex = ["free", "plus", "pro", "prolite", "promax", "team", "business", "enterprise", "edu",
                     "self_serve_business_prolite"].compactMap(CodexUsageMapper.formatCodexPlan)
        let cursor = ["Free", "Pro", "Pro Plus", "Ultra", "Team", "Enterprise"].compactMap {
            CursorUsageMapper.resolvedPlanLabel(planInfoName: $0, membershipType: nil)
        }
        let antigravity = ["Antigravity Starter Quota", "Google AI Pro", "Google AI Ultra",
                           "Gemini Code Assist in Google One AI Pro"].compactMap(AntigravityUsageMapper.formatPlan)
            + AntigravityUsageMapper.paidTierPlans.values
        let copilot = try ["individual", "business", "enterprise", "free", "individual_pro"].compactMap {
            try CopilotUsageMapper.map(body: ["copilot_plan": $0, "token_based_billing": true]).plan
        }
        let grok = try ["SuperGrok", "SuperGrok Heavy", "X Premium+", "Free"].compactMap {
            GrokUsageMapper.planName(from: HTTPResponse(statusCode: 200, headers: [:], body: try json(["subscription_tier_display": $0])))
        }
        let ollama = try ["free", "pro", "max"].compactMap { raw -> String? in
            guard case .named(let name) = OllamaUsageMapper.plan(from: try json(["plan": raw])) else { return nil }
            return name
        }
        let openRouter = [true, false].compactMap { OpenRouterUsageMapper.keyMetrics(from: ["is_free_tier": $0]).plan }
        let zai = try ["GLM Coding Lite", "GLM Coding Pro", "GLM Coding Max"].compactMap {
            ZAIUsageMapper.planName(from: try json(["data": [["productName": $0]]]))
        }
        XCTAssertEqual(antigravity.first, "Antigravity Starter Quota")
        XCTAssertEqual(openRouter, ["Free", "Pay-as-you-go"])
        XCTAssertEqual(zai, ["GLM Coding Lite", "GLM Coding Pro", "GLM Coding Max"])
        return [(.claude, claude), (.codex, codex), (.cursor, cursor), (.antigravity, antigravity), (.copilot, copilot),
                (.grok, grok), (.ollama, ollama), (.opencodeGo, [OpenCodeUsageMapper.plan]), (.openrouter, openRouter),
                (.zai, zai)]
    }

    private func account(_ kind: ProviderKind, _ name: String) -> DashboardAccount {
        DashboardAccount(provider: Provider(id: "\(kind.rawValue)@1", displayName: kind.displayName,
                                            icon: kind.iconSource, accountLabel: name), lines: [])
    }

    /// The header, naming the account when `naming` whether or not that fits.
    private func header(kind: ProviderKind, name: String, plan: String, naming: Bool = false) -> some View {
        let account = account(kind, name)
        return DashboardProviderHeader(provider: account.provider, account: naming ? account : nil, plan: plan) {
            ProviderIcon(source: account.provider.icon, inset: 0.04)
        }
    }

    private func meter(left: Double, limit: Double) -> WidgetData {
        var data = WidgetData(title: "On-demand", icon: .providerMark("cursor"), kind: .dollars, used: limit - left, limit: limit)
        data.displayMode = .remaining
        return data
    }

    /// The width a view asks for when nothing constrains it.
    private func idealWidth(_ view: some View) -> CGFloat {
        NSHostingView(rootView: view.fixedSize().environment(AccountRenameStore?.none)).fittingSize.width
    }
}

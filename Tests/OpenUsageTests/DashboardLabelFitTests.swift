import AppKit
import SwiftUI
import XCTest
@testable import OpenUsage

/// Every metric title, plan and value a provider can produce renders at full size in the panel: no
/// title or plan truncates, and no value shrinks to fit its column. Plans are the providers' official
/// names, never shortened to fit; a long account name truncates instead.
@MainActor
final class DashboardLabelFitTests: XCTestCase {
    /// A provider's card: the panel minus its margin on each side.
    private let cardWidth = PanelMetrics.width - 2 * PanelMetrics.margin

    func testEveryProvidersMetricTitlesFitTheLabelColumn() {
        for kind in ProviderKind.allCases {
            let runtime = AccountProviderRuntime(account: Account(kind: kind, label: kind.displayName), vault: InMemoryCredentialVault())
            for descriptor in runtime.widgetDescriptors where !descriptor.sample.showsResetExpiries {
                let title = descriptor.sample.title
                XCTAssertLessThanOrEqual(
                    idealWidth(Text(title).font(.system(size: DashboardMetricLine.fontSize))),
                    DashboardMetricLine.labelWidth, "\(kind.displayName): \(title)"
                )
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

    /// Each plan a mapper can name fits in its card's header beside the provider's own name, which is
    /// what an account nobody renamed is called.
    func testEveryPlanFitsInItsCardsHeader() throws {
        for (kind, plans) in try plansByProvider() {
            XCTAssertFalse(plans.isEmpty, kind.displayName)
            for plan in plans {
                let width = idealWidth(header(kind: kind, name: kind.displayName, plan: plan))
                XCTAssertLessThanOrEqual(width, cardWidth, "\(kind.displayName): \(plan)")
            }
        }
    }

    /// Robin's accounts, names and plans, as each card draws them: a one-account card in its header, a
    /// card with several accounts on each account's name line.
    func testRobinsAccountsFitWithoutTruncating() {
        var resets = WidgetData(title: "Rate Limit Resets", icon: .providerMark("codex"), kind: .count, used: 2, limit: nil)
        resets.values = [MetricValue(number: 2, kind: .count, label: "available")]
        resets.showsResetExpiries = true
        let soleAccounts: [(ProviderKind, String, String, WidgetData?)] = [
            (.codex, "Sunstory", "Pro 200", resets), (.openrouter, "OpenRouter", "Pay-as-you-go", nil),
            (.opencodeGo, "OpenCode Go", "Go", nil), (.opencodeGo, "Go Basic", "Go", nil),
            (.grok, "Grok Account", "SuperGrok Heavy", nil), (.ollama, "Ollama", "Free", nil),
            (.cursor, "rob@sunstory.com", "Ultra", nil), (.copilot, "robinebers", "Individual", nil),
        ]
        for (kind, name, plan, resets) in soleAccounts {
            XCTAssertLessThanOrEqual(idealWidth(header(kind: kind, name: name, plan: plan, resets: resets)), cardWidth, name)
        }
        let accountLines: [(ProviderKind, String, String)] = [
            (.claude, "Personal", "Max 20x"), (.claude, "Attention Machine 1", "Team 5x"),
            (.claude, "Attention Machine 2", "Team 5x"),
        ]
        for (kind, name, plan) in accountLines {
            let section = DashboardAccountSection(account: account(kind, name), badges: AccountBadges(plan: plan)) { _ in EmptyView() }
            XCTAssertLessThanOrEqual(idealWidth(section.accountLine), cardWidth - 2 * DashboardBox.inset, name)
        }
    }

    /// Beside a name too long for its line, the plan keeps its full width and the name gives way. Robin's
    /// Antigravity accounts sit on account lines; a one-account card carries them in its header.
    func testALongAccountNameTruncatesBeforeThePlan() throws {
        let plan = "Antigravity Starter Quota"
        let tagWidth = idealWidth(PlanTag(plan: plan))
        let tagInk = try inkWidth(PlanTag(plan: plan))
        let longName = "robin.ebers.and.a.long.alias@gmail.com"
        let lineWidth = cardWidth - 2 * DashboardBox.inset
        for name in ["robin.ebers@gmail.com", "rob@sunstory.com", longName] {
            let line = DashboardAccountSection(account: account(.antigravity, name), badges: AccountBadges(plan: plan)) { _ in EmptyView() }
                .accountLine
            if name == longName { XCTAssertGreaterThan(idealWidth(line), lineWidth, "the name must overflow its line") }
            let drawn = try inkWidth(line.frame(width: lineWidth), from: lineWidth - tagWidth, to: lineWidth)
            XCTAssertEqual(drawn, tagInk, accuracy: 0.5, "\(name): the plan drew \(drawn) pt wide, not \(tagInk)")
        }
        let soleAccount = header(kind: .antigravity, name: longName, plan: plan)
        XCTAssertGreaterThan(idealWidth(soleAccount), cardWidth, "the name must overflow the header")
        let end = cardWidth - DashboardBox.inset
        let drawn = try inkWidth(soleAccount.frame(width: cardWidth), from: end - tagWidth, to: end)
        XCTAssertEqual(drawn, tagInk, accuracy: 0.5, "header: the plan drew \(drawn) pt wide, not \(tagInk)")
    }

    /// The wider label and value columns come out of the panel's width, not the meter's: the bar keeps
    /// the length it had at 320 pt with 72 and 44 pt columns, within 2 pt.
    func testTheMeterKeepsItsLength() {
        let columns = DashboardMetricLine.labelWidth + DashboardMetricLine.valueWidth + DashboardMetricLine.resetWidth
            + 3 * DashboardMetricLine.columnSpacing
        XCTAssertGreaterThanOrEqual(cardWidth - 2 * DashboardBox.inset - columns, 66)
    }

    func testWholeDollarValuesDropTheirCents() {
        XCTAssertEqual(meter(left: 500, limit: 500).valueText, "$500")
        XCTAssertEqual(meter(left: 37.42, limit: 100).valueText, "$37.42")
        XCTAssertEqual(meter(left: 2.5, limit: 2.5).valueText, "$2.50")
        XCTAssertEqual(meter(left: 0.004, limit: 100).valueText, "$0")
        XCTAssertEqual(meter(left: 1_234, limit: 2_000).valueText, "$1.2K")
    }

    /// The value column draws each value at its natural width: it neither shrinks nor truncates.
    func testValuesRenderAtFullSize() throws {
        let font = NSFont.monospacedDigitSystemFont(ofSize: DashboardMetricLine.fontSize, weight: .medium)
        let width = cardWidth - 2 * DashboardBox.inset
        let end = width - DashboardMetricLine.resetWidth - DashboardMetricLine.columnSpacing
        for (left, limit) in [(500.0, 500.0), (999.99, 1_000), (12_345, 20_000), (37.42, 100)] {
            let data = meter(left: left, limit: limit)
            let natural = (data.valueText as NSString).size(withAttributes: [.font: font]).width
            XCTAssertLessThanOrEqual(natural, DashboardMetricLine.valueWidth, data.valueText)
            let drawn = try inkWidth(DashboardMetricLine(data: data).frame(width: width),
                                     from: end - DashboardMetricLine.valueWidth, to: end)
            let alone = try inkWidth(Text(data.valueText).font(.system(size: DashboardMetricLine.fontSize, weight: .medium))
                .monospacedDigit().fixedSize())
            XCTAssertEqual(drawn, alone, accuracy: 0.5, "\(data.valueText) drew \(drawn) pt wide, not \(alone)")
        }
        var critical = WidgetData(title: "Weekly", icon: .providerMark("claude"), kind: .percent, used: 100, limit: 100)
        critical.displayMode = .used
        let flame = idealWidth(Image(systemName: "flame.fill").font(.system(size: DashboardMetricLine.fontSize - 3)))
        let percent = ("100%" as NSString).size(withAttributes: [.font: font]).width
        XCTAssertLessThanOrEqual(flame + 2 + percent, DashboardMetricLine.valueWidth, "a spent meter's flame and 100%")
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

    private func header(kind: ProviderKind, name: String, plan: String, resets: WidgetData? = nil) -> some View {
        let account = account(kind, name)
        let card = DashboardProviderCard(
            family: DashboardFamily(id: kind.rawValue, provider: account.provider, accounts: [account]),
            badges: { _ in AccountBadges(resets: resets, plan: plan) }
        ) { _ in EmptyView() }
        return card.header
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

    /// The width of a view's ink between two x positions (its whole width by default), in points.
    private func inkWidth(_ view: some View, from start: CGFloat = 0, to end: CGFloat? = nil) throws -> CGFloat {
        let scale: CGFloat = 2
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light).environment(AccountRenameStore?.none))
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let columns = Int(start * scale)..<(end.map { Int($0 * scale) } ?? image.width)
        let inked = columns.filter { x in (0..<image.height).contains { pixels[($0 * image.width + x) * 4 + 3] > 60 } }
        let first = try XCTUnwrap(inked.first), last = try XCTUnwrap(inked.last)
        return CGFloat(last - first + 1) / scale
    }
}

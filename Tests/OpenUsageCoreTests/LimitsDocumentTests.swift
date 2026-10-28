import XCTest
@testable import OpenUsageCore

final class LimitsArgumentsTests: XCTestCase {
    func testNoArgumentsReadsEveryAccount() {
        XCTAssertEqual(LimitsArguments.parse([]), .success(.limits(provider: nil, force: false)))
    }

    func testProviderAndForceInEitherOrder() {
        let expected = Result<LimitsArguments, LimitsArguments.Invalid>.success(.limits(provider: "codex", force: true))
        XCTAssertEqual(LimitsArguments.parse(["codex", "--force"]), expected)
        XCTAssertEqual(LimitsArguments.parse(["--force", "codex"]), expected)
    }

    func testHelpAndVersionWinOverEverythingElse() {
        XCTAssertEqual(LimitsArguments.parse(["codex", "--help"]), .success(.help))
        XCTAssertEqual(LimitsArguments.parse(["--version"]), .success(.version))
    }

    func testUnknownOptionAndSecondProviderAreInvalid() {
        XCTAssertEqual(LimitsArguments.parse(["--nope"]), .failure(.init(message: "Unknown option --nope.")))
        XCTAssertEqual(LimitsArguments.parse(["claude", "codex"]), .failure(.init(message: "Only one provider can be named.")))
    }
}

final class LimitsProjectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// The line label behind each dashboard row, as the Mac app's runtimes declare them.
    private static let labels: [String: String] = [
        "session": "Session", "usage": "Total usage", "balance": "Balance", "credits": "Credits",
        "rateLimitResets": "Rate Limit Resets", "chat": "Chat", "payAsYouGo": "Pay as you go"
    ]

    private func entry(
        _ kind: ProviderKind,
        lines: [MetricLine],
        plan: String? = "Pro",
        refreshedAt: Date? = nil
    ) -> LimitsProjection.Entry {
        let account = Account(kind: kind, label: "Work")
        let snapshot = ProviderSnapshot(
            providerID: account.cardID, displayName: kind.displayName, plan: plan, lines: lines,
            refreshedAt: refreshedAt ?? now
        )
        return LimitsProjection.Entry(account: account, snapshot: snapshot, metricLabels: Self.labels)
    }

    private func envelope(_ entries: [LimitsProjection.Entry], failures: [LimitsEnvelope.Failure] = []) -> LimitsEnvelope {
        LimitsProjection.envelope(
            entries: entries, failures: failures, order: entries.map(\.account.cardID), now: now, freshFor: 300
        )
    }

    func testBoundedPercentCarriesUsedLimitRemainingUtilizationAndWindow() throws {
        let reset = now.addingTimeInterval(3600)
        let e = entry(.claude, lines: [
            .progress(label: "Session", used: 42, limit: 100, format: .percent, resetsAt: reset, periodDurationMs: 18_000_000)
        ])
        let provider = try XCTUnwrap(envelope([e]).providers[e.account.cardID])
        let session = try XCTUnwrap(provider.resources["session"])
        XCTAssertEqual(session.kind, .consumption)
        XCTAssertEqual(session.unit, "percent")
        XCTAssertEqual(session.used, 42)
        XCTAssertEqual(session.limit, 100)
        XCTAssertEqual(session.remaining, 58)
        XCTAssertEqual(try XCTUnwrap(session.utilization), 0.42, accuracy: 1e-9)
        XCTAssertEqual(session.resetsAt, reset)
        XCTAssertEqual(session.windowSeconds, 18_000)
        XCTAssertEqual(provider.provider, "claude")
        XCTAssertEqual(provider.account, "Work")
        XCTAssertEqual(provider.plan, "Pro")
    }

    func testResourcesCarryTheDashboardTitleWhenKnown() throws {
        let account = Account(kind: .cursor, label: "Work")
        let snapshot = ProviderSnapshot(
            providerID: account.cardID, displayName: "Cursor", plan: nil,
            lines: [.progress(label: "Other Models", used: 3, limit: 100, format: .percent, resetsAt: nil, periodDurationMs: nil)],
            refreshedAt: now
        )
        let entry = LimitsProjection.Entry(
            account: account, snapshot: snapshot, metricLabels: ["api": "Other Models"], titles: ["api": "Other Models"]
        )
        let provider = try XCTUnwrap(envelope([entry]).providers[account.cardID])
        XCTAssertEqual(provider.resources["apiUsage"]?.label, "Other Models")
        let plain = LimitsProjection.Entry(account: account, snapshot: snapshot, metricLabels: ["api": "Other Models"])
        XCTAssertNil(try XCTUnwrap(envelope([plain]).providers[account.cardID]).resources["apiUsage"]?.label)
    }

    func testDocumentReadsBackWhatWasWritten() throws {
        let reset = now.addingTimeInterval(3600)
        let e = entry(.claude, lines: [
            .progress(label: "Session", used: 42, limit: 100, format: .percent, resetsAt: reset, periodDurationMs: 18_000_000)
        ])
        let original = envelope([e])
        let decoded = try LimitsEnvelope.decode(Data(try original.json().utf8))
        XCTAssertEqual(decoded.order, original.order)
        XCTAssertEqual(decoded.providers[e.account.cardID]?.resources["session"]?.used, 42)
        // Timestamps are written to the millisecond, so compare at that precision.
        XCTAssertEqual(try XCTUnwrap(decoded.generatedAt).timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(decoded.providers[e.account.cardID]?.resources["session"]?.resetsAt).timeIntervalSince1970,
                       reset.timeIntervalSince1970, accuracy: 0.001)
    }

    func testDocumentOfAnotherSchemaIsRefused() throws {
        let json = try envelope([]).json().replacingOccurrences(of: "openusage.limits.v1", with: "openusage.limits.v2")
        XCTAssertThrowsError(try LimitsEnvelope.decode(Data(json.utf8))) {
            XCTAssertEqual($0 as? LimitsEnvelope.DecodeError, .unsupportedSchema("openusage.limits.v2"))
        }
    }

    func testPublicKeysDoNotFollowDashboardRowIds() throws {
        let e = entry(.cursor, lines: [
            .progress(label: "Total usage", used: 10, limit: 100, format: .percent)
        ])
        let resources = try XCTUnwrap(envelope([e]).providers[e.account.cardID]).resources
        XCTAssertNotNil(resources["totalUsage"])
        XCTAssertNil(resources["usage"])
    }

    func testBalanceReportsAvailableNotUsed() throws {
        let e = entry(.openrouter, lines: [
            .values(label: "Balance", values: [MetricValue(number: 77.77, kind: .dollars)])
        ])
        let balance = try XCTUnwrap(envelope([e]).providers[e.account.cardID]?.resources["balance"])
        XCTAssertEqual(balance.kind, .balance)
        XCTAssertEqual(balance.unit, "usd")
        XCTAssertEqual(balance.available, 77.77)
        XCTAssertNil(balance.used)
    }

    func testCodexCreditsSplitIntoCountAndDollarValue() throws {
        let e = entry(.codex, lines: [
            .values(label: "Credits", values: [
                MetricValue(number: 821, kind: .count, label: "credits"),
                MetricValue(number: 32.84, kind: .dollars)
            ])
        ])
        let resources = try XCTUnwrap(envelope([e]).providers[e.account.cardID]).resources
        XCTAssertEqual(resources["credits"]?.available, 821)
        XCTAssertEqual(resources["credits"]?.unit, "credits")
        XCTAssertEqual(resources["creditValue"]?.available, 32.84)
        XCTAssertEqual(resources["creditValue"]?.unit, "usd")
    }

    func testResetsNameTheirUnitAndListExpiries() throws {
        let expiry = now.addingTimeInterval(86_400)
        let e = entry(.codex, lines: [
            .values(label: "Rate Limit Resets", values: [MetricValue(number: 2, kind: .count, label: "available")], expiriesAt: [expiry])
        ])
        let resets = try XCTUnwrap(envelope([e]).providers[e.account.cardID]?.resources["rateLimitResets"])
        XCTAssertEqual(resets.unit, "resets")
        XCTAssertEqual(resets.available, 2)
        XCTAssertEqual(resets.expiries, [expiry])
    }

    func testUnboundedProgressOmitsLimitRemainingAndUtilization() throws {
        let e = entry(.copilot, lines: [
            .progress(label: "Chat", used: 7, limit: 0, format: .count(suffix: "messages"))
        ])
        let chat = try XCTUnwrap(envelope([e]).providers[e.account.cardID]?.resources["chat"])
        XCTAssertEqual(chat.used, 7)
        XCTAssertEqual(chat.unit, "messages")
        XCTAssertNil(chat.limit)
        XCTAssertNil(chat.remaining)
        XCTAssertNil(chat.utilization)
    }

    func testTextAndBadgeLinesAreNotLimits() throws {
        let e = entry(.grok, lines: [
            .badge(label: "Pay as you go", text: "2500 cap"),
            .text(label: "Note", value: "hello")
        ])
        XCTAssertEqual(try XCTUnwrap(envelope([e]).providers[e.account.cardID]).resources, [:])
    }

    func testStaleOnceTheRefreshIntervalHasPassed() throws {
        let fresh = entry(.zai, lines: [], refreshedAt: now.addingTimeInterval(-299))
        let old = entry(.zai, lines: [], refreshedAt: now.addingTimeInterval(-300))
        XCTAssertEqual(envelope([fresh]).providers[fresh.account.cardID]?.stale, false)
        let oldProvider = try XCTUnwrap(envelope([old]).providers[old.account.cardID])
        XCTAssertTrue(oldProvider.stale)
        XCTAssertEqual(oldProvider.expiresAt, old.snapshot!.refreshedAt.addingTimeInterval(300))
    }

    func testAccountWithoutSnapshotIsOmittedAndOrderOnlyNamesPresentAccounts() {
        let present = entry(.zai, lines: [])
        let absent = LimitsProjection.Entry(
            account: Account(kind: .claude, label: "Empty"), snapshot: nil, metricLabels: [:]
        )
        let result = LimitsProjection.envelope(
            entries: [absent, present], failures: [],
            order: [absent.account.cardID, present.account.cardID], now: now, freshFor: 300
        )
        XCTAssertEqual(result.order, [present.account.cardID])
        XCTAssertEqual(Array(result.providers.keys), [present.account.cardID])
    }

    func testJSONIsStableAndCarriesTheSchema() throws {
        let e = entry(.zai, lines: [.progress(label: "Session", used: 1, limit: 100, format: .percent)])
        let json = try envelope([e]).json(pretty: false)
        XCTAssertTrue(json.hasPrefix(#"{"errors":[],"generatedAt":"2027-01-15T08:00:00.000Z","order":["#), json)
        XCTAssertTrue(json.contains(#""schema":"openusage.limits.v1""#))
        XCTAssertEqual(try envelope([e]).json(pretty: false), json)
    }
}

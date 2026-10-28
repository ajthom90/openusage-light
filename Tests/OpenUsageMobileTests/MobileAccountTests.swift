import OpenUsageCore
import XCTest
@testable import OpenUsageMobile

final class MobileAccountTests: XCTestCase {
    private func sample() throws -> [MobileAccount] {
        MobileAccount.accounts(in: try LimitsEnvelope.decode(Data(SampleLimits.json().utf8)))
    }

    func testAccountsFollowTheDocumentOrder() throws {
        XCTAssertEqual(try sample().map(\.providerName), ["Claude", "Codex", "OpenRouter"])
    }

    func testPercentMeterShowsUsedAndFraction() throws {
        let session = try XCTUnwrap(try sample()[0].meters.first { $0.id == "session" })
        XCTAssertEqual(session.valueText, "36% used")
        XCTAssertEqual(try XCTUnwrap(session.fraction), 0.36, accuracy: 1e-9)
        XCTAssertNotNil(session.resetsAt)
    }

    func testBalanceShowsDollarsAndNoBar() throws {
        let balance = try XCTUnwrap(try sample()[2].meters.first)
        XCTAssertEqual(balance.valueText, "$12.40 available")
        XCTAssertNil(balance.fraction)
    }

    func testMetersFollowTheDashboardOrderNotTheAlphabet() throws {
        let json = SampleLimits.json().replacingOccurrences(of: "\"session\": {\"kind\": \"consumption\", \"unit\": \"percent\", \"used\": 36", with: "\"fable\": {\"kind\": \"consumption\", \"unit\": \"percent\", \"used\": 1, \"limit\": 100, \"utilization\": 0.01},\n            \"session\": {\"kind\": \"consumption\", \"unit\": \"percent\", \"used\": 36")
        let claude = MobileAccount.accounts(in: try LimitsEnvelope.decode(Data(json.utf8)))[0]
        XCTAssertEqual(claude.meters.map(\.id), ["session", "weekly", "fable"])
    }

    func testAnEmailOnlyNameIsNotShown() throws {
        let json = SampleLimits.json().replacingOccurrences(of: "\"account\": \"Work\"", with: "\"account\": \"me@example.com\"")
        XCTAssertEqual(MobileAccount.accounts(in: try LimitsEnvelope.decode(Data(json.utf8)))[0].name, "")
    }

    func testTitlesAreSpacedAndCapitalised() {
        XCTAssertEqual(MobileAccount.title(for: "rateLimitResets"), "Rate Limit Resets")
        XCTAssertEqual(MobileAccount.title(for: "session"), "Session")
    }

    @MainActor
    func testModelWithoutContainerShowsSampleAndSaysSo() async {
        let model = MobileModel(containerIdentifier: nil, defaults: UserDefaults(suiteName: "mobile-test-\(UUID())")!)
        XCTAssertEqual(model.source, .sample)
        await model.refresh()
        XCTAssertEqual(model.accounts.count, 3)
        XCTAssertNotNil(model.message)
    }
}

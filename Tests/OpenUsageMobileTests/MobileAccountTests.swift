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

    func testHeadlineIsTheFirstBoundedMeterAndWidgetsReadTheSample() throws {
        let snapshot = UsageSnapshot.sample()
        XCTAssertEqual(snapshot.accounts[0].headline?.id, "session")
        XCTAssertEqual(snapshot.accounts[2].headline?.id, "balance")
    }

    func testRemainingReadsWhatIsLeftAndStillColoursByUse() throws {
        let envelope = try LimitsEnvelope.decode(Data(SampleLimits.json().utf8))
        let session = try XCTUnwrap(MobileAccount.accounts(in: envelope, display: .remaining)[0].meters.first { $0.id == "session" })
        XCTAssertEqual(session.valueText, "64% left")
        XCTAssertEqual(session.shortText, "64% left")
        XCTAssertEqual(try XCTUnwrap(session.fraction), 0.64, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(session.usedFraction), 0.36, accuracy: 1e-9)
        let used = try XCTUnwrap(MobileAccount.accounts(in: envelope, display: .used)[0].meters.first { $0.id == "session" })
        XCTAssertEqual(used.shortText, "36%")
    }

    func testTheChoiceFollowsTheMacUnlessOverridden() {
        let defaults = UserDefaults(suiteName: "display-test-\(UUID())")!
        XCTAssertEqual(SharedLimits.resolvedDisplay(from: defaults), .remaining, "the Mac's own default is left")
        SharedLimits.saveMacDisplay("used", to: defaults)
        XCTAssertEqual(SharedLimits.resolvedDisplay(from: defaults), .used)
        SharedLimits.saveChoice(.remaining, to: defaults)
        XCTAssertEqual(SharedLimits.resolvedDisplay(from: defaults), .remaining)
    }

    func testAnAccountThatFailedToRefreshCarriesTheMacsMessage() throws {
        let json = SampleLimits.json().replacingOccurrences(
            of: "\"errors\": []", with: "\"errors\": [{\"providerId\": \"codex@sample2\", \"message\": \"Sign in again\"}]"
        )
        let accounts = MobileAccount.accounts(in: try LimitsEnvelope.decode(Data(json.utf8)))
        XCTAssertNil(accounts[0].notice)
        XCTAssertEqual(accounts[1].notice, "Sign in again")
    }

    func testTitlesAreSpacedAndCapitalised() {
        XCTAssertEqual(MobileAccount.title(for: "rateLimitResets"), "Rate Limit Resets")
        XCTAssertEqual(MobileAccount.title(for: "session"), "Session")
        XCTAssertEqual(MobileAccount.title(for: "apiUsage"), "API Usage")
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

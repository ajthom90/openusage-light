import XCTest
@testable import OpenUsage

/// Locks the burn-rate pacing: the three-state thresholds (ahead / cutting-it-close / behind) and the
/// pace state they resolve to for the notifications. All cases pin `now` and derive `resetsAt` from a
/// target elapsed fraction so the math is deterministic. The bar's colour never reads any of this
/// (`MeterSeverityTests`).
final class PaceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let week: TimeInterval = 7 * 24 * 60 * 60

    /// A reset date such that exactly `elapsed` of the window has gone by as of `now`.
    private func resetsAt(elapsed: Double, period: TimeInterval) -> Date {
        now.addingTimeInterval(period * (1 - elapsed))
    }

    func testZeroUsageHasNoPaceSignal() {
        // Nothing spent → no burn rate to project. Returning a fabricated "ahead" here used to
        // surface a tautological "~100% left at reset" on untouched meters with pacing shown.
        let reset = resetsAt(elapsed: 0.5, period: week)
        XCTAssertNil(Pace.evaluate(used: 0, limit: 100, resetsAt: reset, periodDuration: week, now: now))
    }

    func testEarlyInWindowStillProjectsPace() {
        let reset = resetsAt(elapsed: 0.02, period: week)
        XCTAssertEqual(Pace.evaluate(used: 5, limit: 100, resetsAt: reset, periodDuration: week, now: now)?.status, .behind)
    }

    func testAheadOnTrackBehindThresholds() {
        let reset = resetsAt(elapsed: 0.5, period: week) // half the window gone → projected = used * 2
        let cases: [(used: Double, status: Pace.Status)] = [
            (44, .ahead), (46, .onTrack),
            (50, .onTrack), (60, .behind), (100, .behind), (130, .behind)
        ]

        for testCase in cases {
            XCTAssertEqual(
                Pace.evaluate(used: testCase.used, limit: 100, resetsAt: reset, periodDuration: week, now: now)?.status,
                testCase.status,
                "used: \(testCase.used)"
            )
        }
    }

    func testEvaluateProjectsEndOfPeriodUsage() {
        let reset = resetsAt(elapsed: 0.5, period: week) // half elapsed → projected = used * 2
        let result = Pace.evaluate(used: 30, limit: 100, resetsAt: reset, periodDuration: week, now: now)
        XCTAssertEqual(result?.status, .ahead)
        XCTAssertEqual(result?.projectedUsage ?? 0, 60, accuracy: 0.01)
    }

    func testWindowAlreadyResetReturnsNil() {
        let past = now.addingTimeInterval(-60) // reset already happened
        XCTAssertNil(Pace.evaluate(used: 50, limit: 100, resetsAt: past, periodDuration: week, now: now))
        // Exact-reset boundary: resetsAt == now is already reset, not a live window.
        XCTAssertNil(Pace.evaluate(used: 50, limit: 100, resetsAt: now, periodDuration: week, now: now))
    }

    // MARK: PaceState (the pace verdict the notifications read)

    private func pacedData(
        used: Double,
        elapsed: Double = 0.5,
        period: TimeInterval? = nil,
        displayMode: WidgetDisplayMode = .used
    ) -> WidgetData {
        let period = period ?? week
        var data = WidgetData(title: "Weekly", icon: .providerMark("codex"), kind: .percent,
                              used: used, limit: 100, displayMode: displayMode)
        data.resetsAt = resetsAt(elapsed: elapsed, period: period)
        data.periodDurationMs = Int(period * 1000)
        return data
    }

    func testNoPaceVerdictWithoutAResetWindow() {
        var data = WidgetData(title: "Credits", icon: .providerMark("codex"), kind: .dollars,
                              used: 12, limit: 20)
        XCTAssertEqual(data.paceState(now: now), .unpaced) // no reset window at all
        data.resetsAt = now.addingTimeInterval(week)
        XCTAssertEqual(data.paceState(now: now), .unpaced) // reset date but unknown period
    }

    func testThePaceVerdictPicksThePaceState() {
        XCTAssertEqual(pacedData(used: 30).paceState(now: now), .healthy)
        XCTAssertEqual(pacedData(used: 46).paceState(now: now), .closeToLimit)
        XCTAssertEqual(pacedData(used: 60).paceState(now: now), .runningOut)
        // Projected barely over the limit is still red.
        XCTAssertEqual(pacedData(used: 50.2).paceState(now: now), .runningOut)
    }

    func testZeroUsageHasNoPaceState() {
        // An untouched meter has no pace story.
        XCTAssertEqual(pacedData(used: 0).paceState(now: now), .unpaced)
    }

    func testSpentOutranksThePaceVerdict() {
        XCTAssertEqual(pacedData(used: 100).paceState(now: now), .spent)
        let nearlyEmpty = WidgetData(title: "Credits", icon: .providerMark("codex"), kind: .dollars,
                                     used: 99.999, limit: 100)
        XCTAssertEqual(nearlyEmpty.paceState(now: now), .spent)
        let withHeadroom = WidgetData(title: "Credits", icon: .providerMark("codex"), kind: .dollars,
                                      used: 99.0, limit: 100)
        XCTAssertEqual(withHeadroom.paceState(now: now), .unpaced)

        var data = WidgetData(title: "Weekly", icon: .providerMark("codex"), kind: .percent,
                              used: 99.6, limit: 100)
        data.resetsAt = resetsAt(elapsed: 0.997, period: week)
        data.periodDurationMs = Int(week * 1000)
        XCTAssertEqual(data.paceState(now: now), .spent)
    }

    func testProjectionAtOrRoundedToLimitIsRunningOut() {
        for used in [49.8, 50] {
            XCTAssertEqual(pacedData(used: used).paceState(now: now), .runningOut, "\(used)% used")
        }
    }

    func testSmallButRealCushionStaysAmber() {
        XCTAssertEqual(pacedData(used: 49).paceState(now: now), .closeToLimit)
    }

    func testPlentyRemainingSuppressesFalseRunOutFlame() {
        let session: TimeInterval = 5 * 3600
        let elapsed = 240 / session // four minutes into a five-hour window
        let data = pacedData(used: 2, elapsed: elapsed, period: session)
        // Projection distrusted near-empty: no pace story, never a fabricated projection cushion.
        XCTAssertEqual(data.paceState(now: now), .unpaced)
    }

    func testOnePercentAtProjectionGateDoesNotBecomeRed() {
        let session: TimeInterval = 5 * 3600
        XCTAssertEqual(pacedData(used: 1, elapsed: 0.01, period: session).paceState(now: now), .unpaced)
    }

    func testRunOutFlameShowsOnceFivePercentUsedDespiteHighRemaining() {
        let session: TimeInterval = 5 * 3600
        let elapsed = 240 / session
        let data = pacedData(used: 6, elapsed: elapsed, period: session)
        guard case .runningOut = data.paceState(now: now) else {
            return XCTFail("expected runningOut when burning fast with ≥5% used")
        }
    }

    func testPaceProjectionWaitsUntilWindowHasMateriallyStarted() {
        let session: TimeInterval = 5 * 3600
        let elapsed = 60 / session // one minute in — too early to extrapolate
        let reset = resetsAt(elapsed: elapsed, period: session)
        XCTAssertNil(Pace.evaluate(used: 1, limit: 100, resetsAt: reset, periodDuration: session, now: now))
    }

    func testUntouchedMeterEarlyInItsWindowStaysUnpaced() {
        // Regression: an unstarted window (0 used, e.g. a fresh Cursor billing cycle) used to project
        // a full cushion at reset.
        let data = pacedData(used: 0, elapsed: 0.03)
        XCTAssertEqual(data.paceState(now: now), .unpaced)
    }
}

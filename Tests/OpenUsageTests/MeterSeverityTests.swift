import XCTest
@testable import OpenUsage

/// The meter fill's colour, read off `WidgetData.meterState.severity`, follows the bar's level alone:
/// blue, orange once 75% of the limit is used (a quarter left), red once 90% is (a tenth left),
/// rounded to the whole percent the value shows, and red when the balance rounds to empty (`spent`). A reset window, how much of it has
/// gone, and the pace projection change nothing: a colour that doesn't track the bar makes no sense.
/// It keys off the share *used*, regardless of the Used/Left display mode.
final class MeterSeverityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let week: TimeInterval = 7 * 24 * 60 * 60

    private func percentData(used: Double, limit: Double? = 100,
                             displayMode: WidgetDisplayMode = .used) -> WidgetData {
        WidgetData(title: "Session", icon: .providerMark("codex"), kind: .percent,
                   used: used, limit: limit, displayMode: displayMode)
    }

    /// `elapsed` of a week-long window gone as of `now`.
    private func pacedData(used: Double, elapsed: Double) -> WidgetData {
        var data = percentData(used: used)
        data.resetsAt = now.addingTimeInterval(week * (1 - elapsed))
        data.periodDurationMs = Int(week * 1000)
        return data
    }

    private func severity(_ data: WidgetData) -> WidgetData.MeterSeverity? {
        data.meterState.severity
    }

    /// Robin read Session 83% and Fable 24% left, both blue, as "no colour coding at all": a quarter
    /// left is already orange, a tenth left red.
    func testTheBandsUseRoundedPercentages() {
        let cases: [(used: Double, severity: WidgetData.MeterSeverity)] = [
            (0, .normal), (74, .normal), (74.4, .normal), (74.6, .warning), (75, .warning), (76, .warning),
            (80, .warning), (89.4, .warning), (89.6, .critical), (90, .critical)
        ]

        for testCase in cases {
            XCTAssertEqual(severity(percentData(used: testCase.used)), testCase.severity, "used: \(testCase.used)")
        }
        XCTAssertEqual(percentData(used: 100).meterState, .spent)
        XCTAssertEqual(percentData(used: 130).meterState, .spent)
    }

    /// Robin's panel showed Session 93% red above Fable 27% orange, the orange from a pace projection.
    /// For a fixed share the colour is the same with and without a reset window, however much of the
    /// window has gone: pace tints nothing.
    func testAResetWindowAndTheTimeGoneChangeNothing() {
        for used in stride(from: 0.0, through: 100, by: 1) {
            let plain = severity(percentData(used: used))
            for elapsed in [0.02, 0.2, 0.363, 0.5, 0.9, 0.96, 0.997] {
                XCTAssertEqual(severity(pacedData(used: used, elapsed: elapsed)), plain, "\(used)% used, \(elapsed) of the window gone")
            }
        }
        // The cases the pace verdict used to recolour: 66% burning fast was red, 85% late in the window blue.
        XCTAssertEqual(severity(pacedData(used: 66, elapsed: 0.363)), .normal)
        XCTAssertEqual(severity(pacedData(used: 85, elapsed: 0.96)), .warning)
        XCTAssertEqual(severity(pacedData(used: 27, elapsed: 0.9)), .normal)
        XCTAssertEqual(severity(pacedData(used: 93, elapsed: 0.1)), .critical)
        // Robin's panel: Fable with 24% left is orange, Session with 83% left blue.
        XCTAssertEqual(severity(pacedData(used: 76, elapsed: 0.74)), .warning)
        XCTAssertEqual(severity(pacedData(used: 17, elapsed: 0.25)), .normal)
    }

    /// As the bar fills the colour only ever gets hotter: blue, then orange, then red.
    func testTheColourNeverCoolsAsTheShareUsedRises() {
        func rank(_ severity: WidgetData.MeterSeverity?) -> Int {
            switch severity {
            case nil: return -1
            case .normal: return 0
            case .warning: return 1
            case .critical: return 2
            }
        }
        var previous = -1
        for tenths in 0...1000 {
            let used = Double(tenths) / 10
            let current = rank(severity(pacedData(used: used, elapsed: 0.5)))
            XCTAssertGreaterThanOrEqual(current, previous, "\(used)% used cooled the colour")
            previous = current
        }
        XCTAssertEqual(previous, 2)
    }

    func testRemainderRoundingToZeroIsSpent() {
        // 99.6% used: the 0.4% remaining rounds to "0% left", so the balance reads empty.
        XCTAssertEqual(pacedData(used: 99.6, elapsed: 0.997).meterState, .spent)
        // A dollar metric one rounding-step from empty ($0.004 of $100 left → "$0.00") reads as spent.
        let dollars = WidgetData(title: "Credits", icon: .providerMark("codex"), kind: .dollars,
                                 used: 99.996, limit: 100)
        XCTAssertEqual(dollars.meterState, .spent)
    }

    func testSeverityIgnoresTheUsedLeftDisplayMode() {
        // In Left mode the bar *fill* shows the remaining share, but the colour still keys off usage.
        XCTAssertEqual(severity(percentData(used: 95, displayMode: .remaining)), .critical)
        XCTAssertEqual(severity(percentData(used: 76, displayMode: .remaining)), .warning)
        XCTAssertEqual(severity(percentData(used: 5, displayMode: .remaining)), .normal)
    }

    func testNonPercentKindsBandOnTheirShareOfTheLimit() {
        let dollars = WidgetData(title: "Credits", icon: .providerMark("codex"), kind: .dollars,
                                 used: 45, limit: 50)
        XCTAssertEqual(severity(dollars), .critical) // $5 of $50 left = 10%

        let counts = WidgetData(title: "Requests", icon: .providerMark("codex"), kind: .count,
                                used: 375, limit: 500, countSuffix: "requests")
        XCTAssertEqual(severity(counts), .warning) // 75% used, a quarter left
        XCTAssertEqual(severity(WidgetData(title: "Requests", icon: .providerMark("codex"), kind: .count,
                                           used: 370, limit: 500, countSuffix: "requests")), .normal) // 74% used
    }

    func testUnboundedAndZeroLimitMetricsStayNormal() {
        XCTAssertEqual(severity(percentData(used: 99, limit: nil)), .normal)
        XCTAssertEqual(severity(percentData(used: 99, limit: 0)), .normal)
    }

    func testNoDataHasNoSeverity() {
        var data = percentData(used: 50)
        data.hasData = false
        XCTAssertEqual(data.meterState, .noData)
        XCTAssertNil(severity(data))
    }
}

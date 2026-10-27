import XCTest
@testable import OpenUsage

/// What a dashboard row shows, resolved from its reading for one instant: a bar in the severity's colour
/// with its value and its reset beside it — always, at rest — or a value where the bar would be. The
/// reset follows the clock setting; a window that has not started, a cap without a reset date and a
/// badge leave the reset column empty.
final class DashboardRowModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let week: TimeInterval = 7 * 24 * 3600

    /// A weekly percent window with `elapsed` of it gone, showing what is left.
    private func paced(used: Double, elapsed: Double = 0.5, period: TimeInterval? = nil, title: String = "Weekly") -> WidgetData {
        let period = period ?? week
        var data = WidgetData(title: title, icon: .providerMark("codex"), kind: .percent, used: used, limit: 100)
        data.displayMode = .remaining
        data.resetsAt = now.addingTimeInterval(period * (1 - elapsed))
        data.periodDurationMs = Int(period * 1000)
        return data
    }

    func testABoundedReadingIsABarWithItsValueAndResetAndAnUnboundedOneAValue() {
        let bar = paced(used: 30).dashboardRow(now: now)
        XCTAssertEqual(bar.label, "Weekly")
        XCTAssertEqual(bar.mark, .bar(fill: 0.7, severity: .normal, value: "70%", reset: "3d 12h"))

        var credits = WidgetData(title: "Credits", icon: .providerMark("codex"), kind: .count, used: 452, limit: nil)
        credits.values = [MetricValue(number: 452, kind: .count, label: "credits")]
        XCTAssertEqual(credits.dashboardRow(now: now).mark, .value("452 credits"))

        var resets = WidgetData(title: "Limit Resets", icon: .providerMark("codex"), kind: .count, used: 2, limit: nil)
        resets.values = [MetricValue(number: 2, kind: .count, label: "available")]
        resets.showsResetExpiries = true
        XCTAssertEqual(resets.dashboardRow(now: now).mark, .value("2 available"))
    }

    /// Robin: Session 93% red above Fable 27% orange "makes no sense" — the colour follows the bar's
    /// level alone (orange at 80% used, red at 90%), never the pace. The pace shows as the flame
    /// instead: red while projected to run out before the reset, orange while projected to land inside
    /// the last 10%, none on course, none once spent (the bar is red already), none without a window.
    func testTheColourFollowsTheLevelAndTheFlameFollowsThePace() {
        XCTAssertEqual(paced(used: 60).dashboardRow(now: now).mark, .bar(fill: 0.4, severity: .normal, value: "40%", reset: "3d 12h", flame: .critical))
        XCTAssertEqual(paced(used: 49).dashboardRow(now: now).mark, .bar(fill: 0.51, severity: .normal, value: "51%", reset: "3d 12h", flame: .warning))
        XCTAssertEqual(paced(used: 30).dashboardRow(now: now).mark, .bar(fill: 0.7, severity: .normal, value: "70%", reset: "3d 12h", flame: nil))
        XCTAssertEqual(paced(used: 73, elapsed: 0.9).dashboardRow(now: now).mark, .bar(fill: 0.27, severity: .normal, value: "27%", reset: "16h 48m", flame: nil))
        XCTAssertEqual(paced(used: 85, elapsed: 0.9).dashboardRow(now: now).mark, .bar(fill: 0.15, severity: .warning, value: "15%", reset: "16h 48m", flame: .warning))
        XCTAssertEqual(paced(used: 93, elapsed: 0.2).dashboardRow(now: now).mark, .bar(fill: 0.07, severity: .critical, value: "7%", reset: "5d 14h", flame: .critical))
        XCTAssertEqual(paced(used: 100).dashboardRow(now: now).mark, .bar(fill: 0, severity: .critical, value: "0%", reset: "3d 12h", flame: nil))
        var noWindow = WidgetData(title: "Credits", icon: .providerMark("codex"), kind: .dollars, used: 90, limit: 100)
        noWindow.displayMode = .remaining
        XCTAssertEqual(noWindow.dashboardRow(now: now).mark, .bar(fill: 0.1, severity: .critical, value: "$10", reset: nil, flame: nil))
    }

    func testTheResetFollowsTheClockSettingAndReadsSoonWhenDue() {
        var data = paced(used: 30)
        data.resetDisplayMode = .absolute
        XCTAssertEqual(data.compactResetText(now: now), Formatters.compactClock(data.resetsAt!, now: now))
        data.resetDisplayMode = .relative
        data.resetsAt = now.addingTimeInterval(86 * 60)
        XCTAssertEqual(data.compactResetText(now: now), "1h 26m")
        data.resetsAt = now.addingTimeInterval(-1)
        XCTAssertEqual(data.compactResetText(now: now), "soon")
    }

    func testAFreshSessionACapWithoutAResetAndABadgeLeaveTheResetEmpty() {
        var fresh = paced(used: 0, elapsed: 0.1, period: 5 * 3600, title: "Session")
        fresh.sessionStartSignal = .zeroUsage
        XCTAssertEqual(fresh.dashboardRow(now: now).mark, .bar(fill: 1, severity: .normal, value: "100%", reset: nil))

        let dollars = WidgetData(title: "On-demand", icon: .providerMark("cursor"), kind: .dollars, used: 12, limit: 20)
        XCTAssertEqual(dollars.dashboardRow(now: now).mark, .bar(fill: 0.6, severity: .normal, value: "$12", reset: nil))

        var badge = paced(used: 30)
        badge.valueTextOverride = "Disabled"
        badge.subtitleOverride = "Rate limited"
        XCTAssertEqual(badge.dashboardRow(now: now).mark, .bar(fill: 0.7, severity: .normal, value: "Disabled", reset: nil))
    }
}

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
    /// level alone (orange at 80% used, red at 90%), never the pace. The pace still says when a row
    /// runs out, for the resets popover.
    func testTheColourFollowsTheLevelAndTheRunOutFollowsThePace() {
        let burning = paced(used: 60)
        XCTAssertEqual(burning.dashboardRow(now: now).mark, .bar(fill: 0.4, severity: .normal, value: "40%", reset: "3d 12h"))
        XCTAssertEqual(burning.runsOutAt(now: now), now.addingTimeInterval(Pace.secondsToRunOut(used: 60, limit: 100, resetsAt: burning.resetsAt!, periodDuration: week, now: now)!))

        XCTAssertEqual(paced(used: 73, elapsed: 0.9).dashboardRow(now: now).mark, .bar(fill: 0.27, severity: .normal, value: "27%", reset: "16h 48m"))
        XCTAssertEqual(paced(used: 85, elapsed: 0.9).dashboardRow(now: now).mark, .bar(fill: 0.15, severity: .warning, value: "15%", reset: "16h 48m"))
        XCTAssertEqual(paced(used: 93, elapsed: 0.2).dashboardRow(now: now).mark, .bar(fill: 0.07, severity: .critical, value: "7%", reset: "5d 14h"))
        XCTAssertNil(paced(used: 30).runsOutAt(now: now), "a row on course has no run-out")
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

/// The resets popover's nodes: every instant the account resets or runs out, soonest first, windows
/// that reset together on one node, a red run-out node with its runway, the hovered metric's nodes
/// emphasized.
final class AccountResetsTimelineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let week: TimeInterval = 7 * 24 * 3600

    private func line(_ title: String, used: Double, elapsed: Double = 0.5, period: TimeInterval? = nil, limit: Double? = 100) -> DashboardLine {
        var data = WidgetData(title: title, icon: .providerMark("claude"), kind: .percent, used: used, limit: limit)
        data.displayMode = .remaining
        if let period {
            data.resetsAt = now.addingTimeInterval(period * (1 - elapsed))
            data.periodDurationMs = Int(period * 1000)
        }
        return DashboardLine(descriptor: WidgetDescriptor(id: title.lowercased(), providerID: "claude", metricLabel: title, sample: data), data: data)
    }

    func testNodesAreSoonestFirstWindowsThatResetTogetherShareOneAndARunOutIsRed() {
        let lines = [
            line("Session", used: 30, elapsed: 0.4, period: 5 * 3600),
            line("Weekly", used: 30, period: week),
            line("Fable", used: 60, period: week),
        ]
        let nodes = AccountResetsTimeline.nodes(for: lines, hovered: "fable", now: now)
        XCTAssertEqual(nodes.map(\.title), ["Session resets", "Fable runs out", "Weekly, Fable reset"])
        XCTAssertEqual(nodes.map(\.severity), [.normal, .critical, .normal])
        XCTAssertEqual(nodes.map(\.emphasized), [false, true, true])
        XCTAssertEqual(nodes.map(\.runway), [nil, "A day before it resets", nil])
        XCTAssertEqual(nodes[0].when, Formatters.dayClock(now.addingTimeInterval(3 * 3600), now: now) + " · in 3h")
        XCTAssertEqual(nodes[2].date, now.addingTimeInterval(week / 2))
        XCTAssertEqual(nodes[1].date, lines[2].data.runsOutAt(now: now))
    }

    func testAFreshSessionAnUncappedReadingAndACapWithoutAResetAddNoNode() {
        var fresh = line("Session", used: 0, elapsed: 0.1, period: 5 * 3600)
        var data = fresh.data
        data.sessionStartSignal = .zeroUsage
        fresh = DashboardLine(descriptor: fresh.descriptor, data: data)
        let lines = [fresh, line("Credits", used: 452, limit: nil), line("On-demand", used: 12)]
        XCTAssertEqual(AccountResetsTimeline.nodes(for: lines, hovered: nil, now: now), [])
    }

    func testTheRunwayReadsInHoursDaysOrJustBefore() {
        func runway(_ hours: Double) -> String? {
            AccountResetsTimeline.runway(from: now, to: now.addingTimeInterval(hours * 3600))
        }
        XCTAssertNil(runway(0))
        XCTAssertNil(runway(-2))
        XCTAssertEqual(runway(0.5), "Just before it resets")
        XCTAssertEqual(runway(1), "1 hour before it resets")
        XCTAssertEqual(runway(5.2), "5 hours before it resets")
        XCTAssertEqual(runway(24), "A day before it resets")
        XCTAssertEqual(runway(36), "2 days before it resets")
        XCTAssertEqual(runway(72), "3 days before it resets")
    }

    func testWhenReadsTheDayThenTheDistanceOrSoon() {
        let later = now.addingTimeInterval(3 * 3600 + 50 * 60)
        XCTAssertEqual(AccountResetsTimeline.when(later, now: now), Formatters.dayClock(later, now: now) + " · in 3h 50m")
        let imminent = now.addingTimeInterval(4 * 60)
        XCTAssertEqual(AccountResetsTimeline.when(imminent, now: now), Formatters.dayClock(imminent, now: now) + " · soon")
    }
}

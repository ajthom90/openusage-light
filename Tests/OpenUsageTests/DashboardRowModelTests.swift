import XCTest
@testable import OpenUsage

/// What a dashboard row shows at rest and says under the pointer, resolved from its reading for one
/// instant: a bar or a value, then "64% left · resets in 2h 41m", "41% left · runs out in 1d 8h" in red,
/// the clock form under that setting, and the shorter candidates a narrow slot falls back to.
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

    private func texts(_ row: DashboardRowModel) -> [String] {
        row.hoverCandidates.map { $0.map(\.text).joined(separator: " ") }
    }

    func testABoundedReadingIsABarAndAnUnboundedOneAValue() {
        let bar = paced(used: 30).dashboardRow(now: now)
        XCTAssertEqual(bar.label, "Weekly")
        XCTAssertEqual(bar.mark, .bar(fill: 0.7, severity: .normal))
        XCTAssertEqual(bar.reading.map(\.text), ["70%", "left"])
        XCTAssertEqual(bar.reading.map(\.role), [.value, .unit])
        XCTAssertTrue(bar.hasReading)

        var credits = WidgetData(title: "Credits", icon: .providerMark("codex"), kind: .count, used: 452, limit: nil)
        credits.values = [MetricValue(number: 452, kind: .count, label: "credits")]
        let value = credits.dashboardRow(now: now)
        XCTAssertEqual(value.mark, .value("452 credits"))
        XCTAssertFalse(value.hasReading)
        XCTAssertEqual(value.hoverCandidates, [[]])

        var resets = WidgetData(title: "Limit Resets", icon: .providerMark("codex"), kind: .count, used: 2, limit: nil)
        resets.values = [MetricValue(number: 2, kind: .count, label: "available")]
        resets.showsResetExpiries = true
        XCTAssertEqual(resets.dashboardRow(now: now).mark, .value("2 available"))
    }

    func testTheHoverTextSaysTheResetAndFallsBackToShorterForms() {
        XCTAssertEqual(texts(paced(used: 30).dashboardRow(now: now)), [
            "70% left · resets in 3d 12h", "70% left · in 3d 12h", "70% left",
        ])
        XCTAssertEqual(paced(used: 30).dashboardRow(now: now).tails.last, [], "the reading alone is the floor")
    }

    func testARunningOutRowSaysItsRunwayInRedBeforeItsReset() {
        let data = paced(used: 60)
        let runway = Formatters.compactDuration(Pace.secondsToRunOut(used: 60, limit: 100, resetsAt: data.resetsAt!, periodDuration: week, now: now)!)!
        let row = data.dashboardRow(now: now)
        XCTAssertEqual(row.mark, .bar(fill: 0.4, severity: .critical))
        XCTAssertEqual(texts(row), [
            "40% left · runs out in \(runway) · resets in 3d 12h",
            "40% left · runs out in \(runway)",
            "40% left · out in \(runway)",
            "40% left",
        ])
        XCTAssertEqual(row.reading.map(\.tint), [.critical, .critical], "a red row's value reads red")
        XCTAssertEqual(row.tails[0].map(\.tint), [.critical, nil], "the runway is red, the reset isn't")
        XCTAssertEqual(data.runsOutAt(now: now), now.addingTimeInterval(Pace.secondsToRunOut(used: 60, limit: 100, resetsAt: data.resetsAt!, periodDuration: week, now: now)!))
    }

    func testACloseRowSaysSoInOrange() {
        let row = paced(used: 46).dashboardRow(now: now)
        XCTAssertEqual(row.mark, .bar(fill: 0.54, severity: .warning))
        XCTAssertEqual(texts(row), [
            "54% left · close at this pace · resets in 3d 12h", "54% left · resets in 3d 12h", "54% left · in 3d 12h", "54% left",
        ])
        XCTAssertEqual(row.tails[0].map(\.tint), [.warning, nil])
        XCTAssertNil(paced(used: 30).runsOutAt(now: now), "a blue row has no run-out")
    }

    func testTheHoverTextFollowsTheClockSetting() {
        var data = paced(used: 30)
        data.resetDisplayMode = .absolute
        XCTAssertEqual(texts(data.dashboardRow(now: now))[0], "70% left · resets \(Formatters.compactClock(data.resetsAt!, now: now))")
        data.resetsAt = now.addingTimeInterval(4 * 60)
        XCTAssertEqual(texts(data.dashboardRow(now: now))[0], "70% left · resets soon", "a reset within five minutes reads soon")
    }

    func testAFreshSessionSaysItHasNotStarted() {
        var data = paced(used: 0, elapsed: 0.1, period: 5 * 3600, title: "Session")
        data.sessionStartSignal = .zeroUsage
        let row = data.dashboardRow(now: now)
        XCTAssertEqual(row.mark, .bar(fill: 1, severity: .normal))
        XCTAssertEqual(texts(row), ["100% left · starts when you first use it", "100% left · not started", "100% left"])
    }

    func testACapWithoutAResetNamesItsLimitAndAPlainCountSaysNothing() {
        let dollars = WidgetData(title: "On-demand", icon: .providerMark("cursor"), kind: .dollars, used: 12, limit: 20)
        XCTAssertEqual(texts(dollars.dashboardRow(now: now)), ["$12 used · $20 limit", "$12 used"])
        let count = WidgetData(title: "Requests", icon: .providerMark("cursor"), kind: .count, used: 3, limit: 10)
        XCTAssertEqual(texts(count.dashboardRow(now: now)), ["3 used"])
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

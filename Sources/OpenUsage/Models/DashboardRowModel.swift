import Foundation

/// One metric as the dashboard draws it, resolved from a `WidgetData` for one instant so the bar's colour,
/// the value, the flame and the reset can never disagree. A reading with a limit is a capacity bar filled
/// with what is left (or what is used, under the Used setting) in the severity's colour, its value and
/// its reset beside it, and a flame before the value while the pace is hot; a reading without one shows
/// its value in the bar's place.
struct DashboardRowModel: Equatable {
    enum Mark: Equatable {
        /// A capacity bar: `fill` is the share shown (0...1), tinted by `severity`; `value` is "64%",
        /// "$12", "320"; `reset` is the countdown or clock time, `nil` without a live reset; `flame` is
        /// the pace's colour while it is hot — orange when projected to land inside the last 10%, red
        /// when projected to run out before the reset — and `nil` at rest.
        case bar(fill: Double, severity: WidgetData.MeterSeverity, value: String, reset: String?, flame: WidgetData.MeterSeverity? = nil)
        /// A reading with no limit: its value, where the bar would start.
        case value(String)
    }

    let label: String
    let mark: Mark
}

extension WidgetData {
    /// The row for this reading at `now`.
    func dashboardRow(now: Date = Date()) -> DashboardRowModel {
        guard hasData, isBounded else { return DashboardRowModel(label: title, mark: .value(unboundedDetail)) }
        return DashboardRowModel(
            label: title,
            mark: .bar(
                fill: fraction,
                severity: meterState.severity ?? .normal,
                value: valueText,
                reset: compactResetText(now: now),
                flame: flame(now: now)
            )
        )
    }

    /// The flame's colour while the pace is hot (`paceState(now:)`): orange when cutting it close, red
    /// when running out. `nil` at rest, and once the balance is spent — the bar is already red.
    func flame(now: Date = Date()) -> MeterSeverity? {
        switch paceState(now: now) {
        case .closeToLimit: return .warning
        case .runningOut: return .critical
        case .noData, .spent, .healthy, .unpaced: return nil
        }
    }

    /// The reset column's reading: "1h 40m" as a countdown, or "5:30 PM" / "Wed 4 PM" as a clock time
    /// under that setting; "soon" once the reset is due. `nil` when the row has no live reset: no reset
    /// date, a status badge, or a session window that has not started.
    func compactResetText(now: Date = Date()) -> String? {
        guard hasData, subtitleOverride == nil, let resetsAt, !isFreshSessionWindow(now: now) else { return nil }
        guard resetsAt.timeIntervalSince(now) > 0 else { return Formatters.imminent }
        switch resetDisplayMode {
        case .relative: return Formatters.compactDuration(resetsAt.timeIntervalSince(now))
        case .absolute: return Formatters.compactClock(resetsAt, now: now)
        }
    }
}

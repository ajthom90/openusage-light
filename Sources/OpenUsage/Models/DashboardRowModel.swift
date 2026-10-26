import Foundation

/// One metric as the dashboard draws it: its label, what the row shows at rest, and what it says under
/// the pointer. A reading with a limit is a capacity bar filled with what is left (or what is used, under
/// the Used setting) in the severity's colour; a reading without one shows its value where a bar would
/// end. Under the pointer a bar gives way to its reading, "64% left · resets in 2h 41m", in the same
/// slot. Resolved from a `WidgetData` for one instant, so the colour, the text and the popover can never
/// disagree.
struct DashboardRowModel: Equatable {
    enum Mark: Equatable {
        /// A capacity bar: `fill` is the share shown (0...1), tinted by `severity`.
        case bar(fill: Double, severity: WidgetData.MeterSeverity)
        /// A reading with no limit: its value, right-aligned where a bar would end.
        case value(String)
    }

    /// A run of hover text: the value, its unit word, or a note that follows them.
    struct Span: Equatable {
        enum Role: Equatable {
            case value, unit, note
        }

        let text: String
        let role: Role
        /// A tinted run (red for a runway, orange for a close pace); `nil` reads primary (the value) or
        /// secondary (the rest).
        var tint: WidgetData.MeterSeverity? = nil
    }

    let label: String
    let mark: Mark
    /// Under the pointer a bar gives way to this: the value and its unit word. Empty for a value row.
    let reading: [Span]
    /// What may follow the reading, longest first; the row shows the first that fits. The last is always
    /// empty, so the reading alone is the floor.
    let tails: [[Span]]

    /// The hover text's candidates, longest first: the reading followed by each tail.
    var hoverCandidates: [[Span]] {
        tails.map { reading + $0 }
    }

    /// Whether the row can show anything under the pointer beyond its highlight.
    var hasReading: Bool { !reading.isEmpty }
}

extension WidgetData {
    /// The row for this reading at `now`.
    func dashboardRow(now: Date = Date()) -> DashboardRowModel {
        guard hasData, isBounded else {
            return DashboardRowModel(label: title, mark: .value(unboundedDetail), reading: [], tails: [[]])
        }
        let state = meterState(now: now)
        let severity = state.severity ?? .normal
        let tint: MeterSeverity? = severity == .normal ? nil : severity
        return DashboardRowModel(
            label: title,
            mark: .bar(fill: fraction, severity: severity),
            reading: [
                DashboardRowModel.Span(text: valueText, role: .value, tint: tint),
                DashboardRowModel.Span(text: displayMode.label.lowercased(), role: .unit, tint: tint),
            ],
            tails: hoverTails(state: state, now: now)
        )
    }

    /// When the quota is projected to run out before it resets, that instant.
    func runsOutAt(now: Date = Date()) -> Date? {
        guard case .runningOut = meterState(now: now),
              let limit, let resetsAt, let periodDurationMs, periodDurationMs > 0,
              let seconds = Pace.secondsToRunOut(
                used: used, limit: limit, resetsAt: resetsAt,
                periodDuration: TimeInterval(periodDurationMs) / 1000, now: now
              )
        else { return nil }
        return now.addingTimeInterval(seconds)
    }

    /// "in 2h 41m", or "Tue 5 PM" under the clock setting; "soon" within five minutes.
    func resetPhrase(for date: Date, now: Date = Date()) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 5 * 60 else { return Formatters.imminent }
        switch resetDisplayMode {
        case .relative: return "in " + (Formatters.compactDuration(seconds) ?? Formatters.imminent)
        case .absolute: return Formatters.compactClock(date, now: now)
        }
    }

    private func hoverTails(state: MeterState, now: Date) -> [[DashboardRowModel.Span]] {
        func note(_ text: String, _ tint: MeterSeverity? = nil) -> DashboardRowModel.Span {
            DashboardRowModel.Span(text: "· " + text, role: .note, tint: tint)
        }
        if isFreshSessionWindow(now: now) {
            return [[note("starts when you first use it")], [note("not started")], []]
        }
        guard let resetsAt else {
            // A cap with no reset date says what it is a cap on ("$500 limit"); a plain count says nothing.
            guard kind != .count || periodDurationMs != nil, let subtitle = boundedSubtitle else { return [[]] }
            return [[note(subtitle.prefix(1).lowercased() + subtitle.dropFirst())], []]
        }
        let reset = resetPhrase(for: resetsAt, now: now)
        switch state {
        case .spent, .runningOut:
            guard let runsOut = runsOutAt(now: now) else { return [[note("resets " + reset)], [note(reset)], []] }
            let runway = resetPhrase(for: runsOut, now: now)
            return [
                [note("runs out " + runway, .critical), note("resets " + reset)],
                [note("runs out " + runway, .critical)],
                [note("out " + runway, .critical)],
                [],
            ]
        case .closeToLimit:
            return [[note("close at this pace", .warning), note("resets " + reset)], [note("resets " + reset)], [note(reset)], []]
        case .healthy, .level, .noData:
            return [[note("resets " + reset)], [note(reset)], []]
        }
    }
}

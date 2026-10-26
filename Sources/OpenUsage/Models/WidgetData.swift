import Foundation

/// Everything a tile needs to render one metric.
///
/// A metric with a `limit` has a beginning and an end, so it renders as a capsule meter row.
/// Without a `limit` it's an unbounded amount → a single right-aligned text line.
struct WidgetData: Hashable {
    /// Headline shown on a placed tile with no real backing metric (em dash, U+2014).
    static let noDataHeadline = "—"
    /// Subtitle shown on a placed tile with no real backing metric. Copy is intentionally exact.
    static let noDataSubtitle = "No data"

    let title: String          // "Claude 5h", "Cursor credits"
    let icon: IconSource
    let kind: MetricKind
    let used: Double
    var limit: Double?         // nil => unbounded (number tile); cleared when a .values line resolves
    var countSuffix: String?   // e.g. "credits", "requests"
    var valuePrefix: String?   // e.g. "~" for forecasts
    var displayMode: WidgetDisplayMode = .used
    /// Global relative/absolute reset display, stamped by `WidgetDataStore` (like `displayMode`).
    var resetDisplayMode: ResetDisplayMode = .relative
    var resetsAt: Date?
    /// Zero or more future expiry instants listed in the resets row's popover (Claude and Codex
    /// rate-limit resets — one entry per still-available credit). Empty for every other row. Kept as raw
    /// `Date`s so the popover formats live and follows the global relative/absolute mode.
    var expiriesAt: [Date] = []
    /// Descriptor opt-in marking this as the Claude or Codex rate-limit-resets row. When set, the row's
    /// hover popover is the resets timeline (each credit's expiry, where one is claimed) instead of the
    /// account's resets. Off for every other row.
    var showsResetExpiries: Bool = false
    var periodDurationMs: Int?
    var valueTextOverride: String?
    var subtitleOverride: String?
    /// Fixed trailing word for an unbounded row, e.g. "left" for an extra balance.
    var unboundedValueWord: String?
    /// False when no real provider metric backs this tile. The view then shows a "No data" state
    /// instead of the descriptor's placeholder template numbers. True for real data and direct fixtures.
    var hasData: Bool = true
    /// Raw numbers for an unbounded `.values` row (empty for meters). The view
    /// formats these at render time instead of reading a baked string — see `unboundedDetail`.
    var values: [MetricValue] = []
    /// Which of `values` this widget renders — cost-only, tokens-only, or the combined `.all`. Set by
    /// the descriptor factory, so one provider row can back several tiles and the mapper stays oblivious.
    var selection: ValueSelection = .all
    /// A tray-only unit word appended after this tile's menu-bar value for an unbounded count (e.g. Codex
    /// Rate Limit Resets → "2 resets"). Set by the descriptor, so renaming the tile can't silently drop
    /// the suffix — replaces matching on the tile's title. `nil` for tiles that show the bare value.
    var traySuffix: String?
    /// Session-window meters (Claude/OpenCode rolling 5-hour pools, Antigravity's pools) that read
    /// "Not started" while the window hasn't begun — the value names the signal that detects that state,
    /// because the providers report fresh windows differently (see `SessionStartSignal`). Set by those
    /// descriptors and carried through `WidgetDataStore.resolve`, so the treatment is a descriptor
    /// opt-in rather than a hardcoded widget-ID list in the model. `nil` for every other row.
    var sessionStartSignal: SessionStartSignal?

    /// How a session-window meter tells a not-yet-started window from an in-flight one.
    enum SessionStartSignal: Hashable {
        /// Zero usage is the fresh signal. Antigravity reports a reset instant even for an untouched
        /// window and its mapper rounds the fresh pool's fraction-derived percent to 0, so `used == 0`
        /// is what marks the window as fresh.
        case zeroUsage
        /// A missing reset date is the fresh signal: by the time a row carries one, a reset instant
        /// means the window started. Claude's five-hour block is created by the first message, so it
        /// simply reports no `resets_at` until then; OpenCode does report a placeholder for an untouched
        /// window, which `OpenCodeUsageMapper` drops at capture time. Zero usage is NOT trusted here:
        /// both APIs report utilization in whole percents, so an in-flight window under 1% also reads
        /// 0 (#1160) — the reset date is what tells the two apart.
        case missingResetDate
    }
    var isBounded: Bool { limit != nil }

    /// `values` projected through `selection` — exactly what this tile shows.
    var selectedValues: [MetricValue] { selection.apply(to: values) }

    var displayedValue: Double {
        guard displayMode == .remaining, let limit else { return used }
        return max(0, limit - used)
    }

    /// Bar fill 0...1. Uses the same rounded value the row shows, so the bar and the number never
    /// disagree — a value that reads "0%" draws an empty bar instead of a tiny sliver.
    /// Display-mode-dependent: `remaining/limit` when the meter shows "remaining", `used/limit` when
    /// it shows "used". Use `remainingFraction` when the value must mean "remaining" regardless of
    /// display mode (e.g. quota notifications' under-10% check).
    var fraction: Double {
        guard let limit, limit > 0 else { return 0 }
        return min(max(roundedDisplayValue / limit, 0), 1)
    }

    /// Remaining share of the limit, 0...1, independent of the used/remaining display mode. Quota
    /// notifications use this for the "under 10% remaining" rule so the alert always reflects actual
    /// remaining, whether the row shows used or remaining.
    var remainingFraction: Double {
        guard let limit, limit > 0 else { return 0 }
        return min(max((limit - used) / limit, 0), 1)
    }

    /// Severity bands for the meter fill color (see `MeterState.severity`).
    enum MeterSeverity: Hashable {
        case normal, warning, critical
    }

    /// The meter's full visual state, derived once (`meterState(now:)`) so the bar color and the
    /// resets popover can never contradict each other.
    /// Precedence, highest first: no data → spent → live pace verdict → absolute level bands.
    enum MeterState: Hashable {
        /// No real metric backs the row — gray, empty track.
        case noData
        /// Spent to nothing the user can see: a real zero, or a remainder so small it rounds to
        /// "0" at the value's precision ("0%", "$0.00", "0 credits"). Red. Outranks the pace verdict —
        /// a visibly empty bar is never a calmer color.
        case spent
        /// Projected to run out before the reset (`runsOutAt(now:)` says when), or to land right at the
        /// limit with no cushion to speak of. Red.
        case runningOut
        /// Projected to land inside the last 10% — cutting it close — but still with a cushion of at
        /// least 1%. (A cushion that rounds to 0% promotes to `runningOut` instead.) Orange.
        case closeToLimit
        /// On course to finish with ≥10% to spare. Blue.
        case healthy
        /// No reset window to pace against: color from absolute level bands on the share used.
        case level(MeterSeverity)

        /// Bar fill severity, or `nil` for `noData` (the track stays gray).
        var severity: MeterSeverity? {
            switch self {
            case .noData: return nil
            case .spent, .runningOut: return .critical
            case .closeToLimit: return .warning
            case .healthy: return .normal
            case .level(let severity): return severity
            }
        }
    }

    /// `displayedValue` rounded the same way `format(_:)` rounds it for the row's value.
    private var roundedDisplayValue: Double {
        roundedAtDisplayPrecision(displayedValue)
    }

    /// Rounds a value to the precision this kind shows in its value — whole percent, one-decimal
    /// count, or cents — so the meter geometry and the spent check never disagree with the printed
    /// number. (A value that reads "0%" must register as zero, not a hairline sliver.)
    private func roundedAtDisplayPrecision(_ value: Double) -> Double {
        switch kind {
        case .percent: return value.rounded()
        case .count: return (value * 10).rounded() / 10
        case .dollars: return (value * 100).rounded() / 100
        }
    }

    /// Primary value string for the menu bar and unbounded rows. Returns the no-data
    /// marker when no real metric backs the tile, so no surface can print the descriptor's placeholder
    /// sample numbers as if they were measured usage.
    var valueText: String {
        guard hasData else { return Self.noDataHeadline }
        if let valueTextOverride { return valueTextOverride }
        // A `.values` row's primary reading is its first selected value; meters fall through to the
        // bounded/`used` formatting.
        if let first = selectedValues.first {
            return (valuePrefix ?? "") + MetricFormatter.number(first.number, kind: first.kind, style: .row)
        }
        return (valuePrefix ?? "") + format(displayedValue)
    }

    /// The menu-bar (tray) reading: bounded metrics stay unit-aware (percent meters as %, dollar meters
    /// as compact dollars, count meters as compact counts) while still honoring the global Used/Left
    /// mode through `displayedValue`. Unbounded rows show their selected value compacted through the same
    /// formatter the popover uses. A status badge with no number (e.g. Grok "Disabled") shows its text
    /// rather than a misleading "0".
    var menuBarValue: String {
        guard hasData else { return valueText }
        if let limit, limit > 0 {
            if kind == .percent {
                // Percent is the only bounded unit that should collapse to a tray percentage. Clamp both
                // ends so a provider sample can never print "-5%" or "105%" beside the icon.
                let percent = min(100, max(0, Int((displayedValue / limit * 100).rounded())))
                return "\(percent)%"
            }
            return MetricFormatter.number(displayedValue, kind: kind, style: .tray)
        }
        if let first = selectedValues.first {
            if let traySuffix, first.kind == .count {
                return "\(MetricFormatter.number(first.number, kind: .count, style: .tray)) \(traySuffix)"
            }
            return MetricFormatter.string(for: first, style: .tray)
        }
        if let valueTextOverride { return valueTextOverride }
        let number = MetricFormatter.number(displayedValue, kind: kind, style: .tray)
        if kind == .count, let countSuffix { return "\(number) \(countSuffix)" }
        return number
    }

    /// Right-aligned descriptive line for an unbounded row (no bar): just "<value> <word>". The word is
    /// `unboundedValueWord` when set (extras always read "1,503 left", spend rows "$12.34 spent");
    /// otherwise it falls back to the global left/used mode word.
    var unboundedDetail: String {
        guard hasData else { return Self.noDataSubtitle }
        if let valueTextOverride { return valueTextOverride }
        let selected = selectedValues
        if !selected.isEmpty {
            // One value: a lone dollar amount takes the widget's trailing word ("$4.08 spent",
            // "$1,503 left"); any other single value carries its own unit label ("1.2M tokens",
            // "2 available"). Several values join into the combined reading ("$4.08 · 1.2M tokens").
            if selected.count == 1 {
                let value = selected[0]
                if value.kind == .dollars, let word = unboundedValueWord {
                    return "\(MetricFormatter.number(value.number, kind: .dollars, style: .row)) \(word)"
                }
                return MetricFormatter.string(for: value, style: .row)
            }
            return selected.map { MetricFormatter.string(for: $0, style: .row) }.joined(separator: " · ")
        }
        // Fallback for an unbounded row without typed values: "<value> <suffix> <word>".
        let word = unboundedValueWord ?? displayMode.label.lowercased()
        if kind == .count, let countSuffix {
            return "\(valueText) \(countSuffix) \(word)"
        }
        return "\(valueText) \(word)"
    }

    /// Color bands for reset-credit expiries: blue normally, orange under a week, red under 48 hours.
    /// A past-due expiry remains critical until the next refresh drops it from the available list.
    static let expiryWarningWindow: TimeInterval = 7 * 24 * 60 * 60
    static let expiryCriticalWindow: TimeInterval = 48 * 60 * 60

    /// Severity band for a single expiry `timeRemaining` seconds out: red under 48h, orange under a
    /// week, blue beyond, for the resets popover's per-credit dots.
    static func expirySeverity(secondsRemaining: TimeInterval) -> MeterSeverity {
        if secondsRemaining <= expiryCriticalWindow { return .critical }
        if secondsRemaining <= expiryWarningWindow { return .warning }
        return .normal
    }

    /// The available reset-credit count backing a `showsResetExpiries` row (its "N available" figure).
    /// Lets the popover tell "no credits" (empty state) from "credits whose per-credit expiries we
    /// couldn't fetch" — the usage-body fallback carries the count but no expiry list, so `expiriesAt`
    /// is empty while the row still reads e.g. "3 available".
    var resetCreditCount: Int {
        Int((selectedValues.first?.number ?? 0).rounded(.down))
    }

    /// Bounded/fallback formatting in the popover row's compact style, so a meter's value always fits
    /// the dashboard's value column at full size. Unbounded `.values` rows format their values directly
    /// (`unboundedDetail`).
    private func format(_ value: Double) -> String {
        MetricFormatter.number(value, kind: kind, style: .row)
    }
}

// MARK: - Pace (meter state)

extension WidgetData {
    /// The inputs pacing needs, present only for a bounded metric with a known reset window. `nil`
    /// short-circuits the live pace verdict (the bar falls back to absolute level bands)
    /// (e.g. unbounded rows, no-data rows, rows whose reset/period cadence is unknown).
    private var paceContext: (limit: Double, resetsAt: Date, period: TimeInterval)? {
        guard hasData, let limit, limit > 0, let resetsAt,
              let periodDurationMs, periodDurationMs > 0 else { return nil }
        return (limit, resetsAt, TimeInterval(periodDurationMs) / 1000)
    }

    /// The meter's state for `now` — the single source the row's colour and the resets popover read from,
    /// so they can't drift apart. Precedence, highest first:
    ///
    /// 1. **No data** → gray, empty.
    /// 2. **Spent** → red, whenever the remainder rounds to zero at the value's precision (a visibly
    ///    empty bar always reads spent, pace aside).
    /// 3. **Live pace verdict** (a reset window): blue `healthy` while ≥10% is projected to spare,
    ///    orange `closeToLimit` when projected inside the last 10% *with a cushion of at least 1%*, red
    ///    `runningOut` when projected to blow past the limit before reset or to land right at it
    ///    (cushion rounds to 0%).
    /// 4. **Absolute level bands** (no window to project against): orange once 80% of the limit is
    ///    used, red once 10% or less is left, rounded to the whole percent the value shows.
    ///
    /// Every band keys off the share *used*, never the displayed fraction, so the colour and copy
    /// don't flip with the Used/Left toggle.
    func meterState(now: Date = Date()) -> MeterState {
        guard hasData, let limit, limit > 0 else { return hasData ? .level(.normal) : .noData }
        if roundedAtDisplayPrecision(limit - used) <= 0 { return .spent }
        // A "Not started" session has nothing to pace yet — a calm bar with an empty reset column.
        if isFreshSessionWindow(now: now) { return absoluteLevelState(used: used, limit: limit) }

        if let ctx = paceContext,
           let result = Pace.evaluate(used: used, limit: ctx.limit, resetsAt: ctx.resetsAt,
                                      periodDuration: ctx.period, now: now) {
            // Coarse whole-percent meters can read 1% used very early in a window; linear extrapolation
            // then projects a bogus blow-out while the value still shows ~99% left. When >95% of the
            // quota clearly remains (used below 5%), distrust the projection entirely and use the
            // absolute level bands instead.
            switch result.status {
            case .ahead:
                return .healthy
            case .onTrack:
                guard used / ctx.limit >= 0.05 else { return absoluteLevelState(used: used, limit: limit) }
                let spare = Int(((1 - result.projectedUsage / ctx.limit) * 100).rounded())
                return spare >= 1 ? .closeToLimit : .runningOut
            case .behind:
                guard used / ctx.limit >= 0.05 else { return absoluteLevelState(used: used, limit: limit) }
                return .runningOut
            }
        }

        return absoluteLevelState(used: used, limit: limit)
    }

    /// Color from the share used when there's no trustworthy pace projection (no reset window, or a
    /// projection deliberately distrusted near-empty): orange at 80% used, red at 90%, blue below.
    private func absoluteLevelState(used: Double, limit: Double) -> MeterState {
        let percentUsed = (min(max(used / limit, 0), 1) * 100).rounded()
        if percentUsed >= 90 { return .level(.critical) }
        if percentUsed >= 80 { return .level(.warning) }
        return .level(.normal)
    }

    /// Session meters only (Claude/Antigravity/OpenCode): a "not started" state for the current window
    /// when nothing has been spent in it yet, detected through the descriptor's `sessionStartSignal`
    /// (see `SessionStartSignal` for why each provider trusts its signal). Both signals read frozen
    /// snapshot fields, not a `resetsAt - now ≈ full period` window-timing test — that test is only
    /// valid the instant the snapshot is captured, then drifts every second until the next refresh,
    /// which split the value from its note ("100% left" while the note fell back to "resets in 5h").
    /// `.zeroUsage` is additionally gated on `now < resetsAt`: once the reset has passed the snapshot
    /// is stale, so we drop the "not started" claim and let the row fall back to the normal countdown.
    func isFreshSessionWindow(now: Date = Date()) -> Bool {
        guard let signal = sessionStartSignal, hasData, limit != nil, used <= 0 else { return false }
        switch signal {
        case .zeroUsage:
            guard let resetsAt else { return false }
            return now < resetsAt
        case .missingResetDate:
            return resetsAt == nil
        }
    }
}

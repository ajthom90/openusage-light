import Foundation

/// Burn-rate pacing for a bounded metric, ported from the original OpenUsage
/// (`src/lib/pace-status.ts`). Given how much of a quota is spent and how far
/// through the reset window we are, it projects usage at the current rate to the end of the window.
/// This drives the notifications; never the bar's colour.
///
/// Pure logic (no SwiftUI) so it stays unit-testable; `WidgetData` turns it into the meter state.
enum Pace {
    enum Status {
        case ahead     // projected to finish with ≥10% of the quota to spare → calm blue
        case onTrack   // projected to land inside the last 10% — cutting it close → orange
        case behind    // projected to blow past the limit before reset → red
    }

    /// Classification plus the projected end-of-period usage (same unit as `used`/`limit`), mirroring the
    /// original's `PaceResult`. `projectedUsage` decides how much cushion an on-track meter keeps.
    struct Result {
        let status: Status
        let projectedUsage: Double
    }

    /// Minimum time into the reset window before burn-rate projection is meaningful — avoids
    /// dividing by a few seconds of elapsed time on a coarse whole-percent meter.
    static func minimumElapsed(periodDuration: TimeInterval) -> TimeInterval {
        max(60, periodDuration * 0.01)
    }

    /// Full pace evaluation, or `nil` when there's no signal (window not started yet, already reset,
    /// too early in the window for a stable projection, or nothing spent yet). Mirrors
    /// `calculatePaceStatus`, minus its zero-usage "ahead": zero usage carries no burn rate to project.
    static func evaluate(used: Double, limit: Double, resetsAt: Date, periodDuration: TimeInterval,
                         now: Date = Date()) -> Result? {
        guard limit > 0, periodDuration > 0, used > 0 else { return nil }
        let elapsed = now.timeIntervalSince(resetsAt.addingTimeInterval(-periodDuration))
        guard elapsed >= minimumElapsed(periodDuration: periodDuration), now < resetsAt else { return nil }

        let projected = used / elapsed * periodDuration
        if used >= limit { return Result(status: .behind, projectedUsage: projected) } // maxed → behind

        let status: Status
        if projected <= limit * 0.9 { status = .ahead }      // ≥10% projected to spare
        else if projected <= limit { status = .onTrack }     // lands inside the last 10%
        else { status = .behind }
        return Result(status: status, projectedUsage: projected)
    }
}

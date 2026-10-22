import Foundation

/// The resets popover's timeline model: which state the body renders and one display-ready entry per
/// reset. Pure and static, so the phrasing and ordering are unit-testable without a view.
extension RateLimitResetsDetail {
    /// What the body renders, resolved once from the count and expiry list so the "empty vs. count-only
    /// vs. timeline" choice is unit-testable and can't drift between the view and its tests.
    enum Content: Equatable {
        case timeline([Entry])
        case unknownExpiries(count: Int)
        case empty
    }

    /// Empty `expiries` is ambiguous: a genuinely empty balance (`count == 0`) shows the empty state,
    /// but a positive `count` with no expiries means the dedicated expiry fetch was unavailable and the
    /// row fell back to the usage-body count — show that count rather than "no resets".
    nonisolated static func content(count: Int, expiries: [Date], now: Date = Date()) -> Content {
        let entries = entries(from: expiries, now: now)
        if !entries.isEmpty { return .timeline(entries) }
        if count > 0 { return .unknownExpiries(count: count) }
        return .empty
    }

    /// One timeline node's display strings, derived from a credit's expiry instant. Pure and static so
    /// the phrasing is unit-testable without a view.
    struct Entry: Identifiable, Equatable {
        let id: Int          // 0-based row index (soonest first)
        let number: Int      // 1-based reset number, shown inside the dot
        let date: Date       // the credit's expiry instant — identity for the claim flow
        let key: Key         // view identity: the expiry plus its ordinal among equal expiries
        let severity: WidgetData.MeterSeverity
        let time: String       // exact expiry, e.g. "Jul 12 at 5:30 PM"; "Expiring soon" when imminent
        let countdown: String? // "12d 18h"; nil when imminent (no useful countdown to show)

        struct Key: Hashable {
            let date: Date
            let ordinal: Int
        }

        var accessibilityLabel: String {
            "Reset \(number), \(time)" + (countdown.map { ", expires in \($0)" } ?? "")
        }
    }

    /// Build the timeline entries from raw expiry instants: sort soonest-first, number from 1, and pair
    /// each exact expiry time with its countdown. A past-due or ≤5-minute expiry can't print a useful
    /// exact time or countdown, so it reads "Expiring soon" with no trailing countdown. Imminence keys
    /// off the *relative* window — `Formatters.whenLabel(.relative)` collapses to `soon` at ≤5 minutes,
    /// while `.absolute` only collapses once past-due — so both formats agree instead of the exact time
    /// printing a wall-clock while the countdown reads "soon".
    nonisolated static func entries(from expiries: [Date], now: Date = Date()) -> [Entry] {
        var seen: [Date: Int] = [:]
        return expiries.sorted().enumerated().map { index, date in
            let ordinal = seen[date, default: 0]
            seen[date] = ordinal + 1
            let relative = Formatters.whenLabel(at: date, mode: .relative, now: now)
            let absolute = Formatters.whenLabel(at: date, mode: .absolute, now: now)
            let imminent = (relative == nil || relative == Formatters.imminent)
            return Entry(
                id: index,
                number: index + 1,
                date: date,
                key: Entry.Key(date: date, ordinal: ordinal),
                severity: WidgetData.expirySeverity(secondsRemaining: date.timeIntervalSince(now)),
                time: (imminent || absolute == nil) ? "Expiring soon" : absolute!,
                countdown: imminent ? nil : relative
            )
        }
    }
}

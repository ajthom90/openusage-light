import Foundation

/// Global choice for how reset countdowns read across every bounded row: a relative duration
/// ("Resets in 4d 17h") or a concrete wall-clock time ("Resets tomorrow at 9:00 AM"). Ported from the
/// original OpenUsage's `resetTimerDisplayMode` setting; chosen in Settings, or flipped by a click on
/// any row's reset time.
/// The labels avoid relative/absolute jargon: they're what each mode looks like.
package enum ResetDisplayMode: String, Hashable, Sendable, CaseIterable {
    case relative
    case absolute

    package var label: String {
        switch self {
        case .relative: return "Countdown"
        case .absolute: return "Exact Time"
        }
    }

    package mutating func toggle() {
        self = self == .relative ? .absolute : .relative
    }
}

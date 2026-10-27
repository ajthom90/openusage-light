import Foundation

/// Antigravity quota widget IDs and metric labels, shared by account runtimes
/// and `AntigravityUsageMapper` so both sides of the exact-string label binding
/// (`WidgetDescriptor.metricLabel` == `MetricLine.label`, resolved in `WidgetDataStore.data(for:)`)
/// come from one place — label drift there is a silent "No data" failure.
///
/// The shared Gemini and non-Gemini (Claude, GPT-OSS) pools each have a rolling 5-hour window plus a
/// weekly window. Eligible accounts also report a separate Gemini 4 Argon weekly quota. The dashboard
/// titles them "Gemini 5h", "Gemini", "Argon", "Claude 5h" and "Claude" (the weekly windows take the
/// plain pool names, since every account has those); the labels below stay the binding keys, so
/// snapshots cached under them keep matching.
/// `geminiID` keeps its historical `antigravity.geminiPro` raw value so existing users' layout state
/// (enabled/pin/order) carries over to the shared meter with zero migration.
package enum AntigravityMetric {
    package static let geminiID = "antigravity.geminiPro"
    package static let geminiWeeklyID = "antigravity.geminiWeekly"
    package static let argonWeeklyID = "antigravity.argonWeekly"
    package static let claudeID = "antigravity.claude"
    package static let claudeWeeklyID = "antigravity.claudeWeekly"

    package static let sessionLabel = "Session"
    package static let weeklyLabel = "Weekly"
    package static let argonWeeklyLabel = "Argon Weekly"
    package static let claudeLabel = "Claude"
    package static let claudeWeeklyLabel = "Claude Weekly"
}

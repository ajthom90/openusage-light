import Foundation

/// Builds the plan name and meters from the subscription response: a Session meter from the 5-hour-class
/// `subs_usage.window` and a Weekly meter from `subs_usage.weekly`. Only those fields and the plan name
/// are read; the response's key, name, and email never leave this function. Pure, so it tests against
/// sample payloads.
package enum MuseCodeUsageMapper {
    package static let sessionLabel = "Session"
    package static let weeklyLabel = "Weekly"
    private static let weekMs = 7 * 24 * 60 * 60 * 1000

    package static func map(_ body: Data) throws -> (plan: String?, lines: [MetricLine]) {
        guard let root = ProviderParse.jsonObject(body) else { throw MuseCodeUsageError.invalidResponse }
        let plan = (root["subs_tier_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        guard let usage = root["subs_usage"] as? [String: Any] else {
            // A signed-in account without a subscription has nothing to meter; say so plainly.
            if (root["is_subs_active"] as? Bool) == false { throw MuseCodeUsageError.noSubscription }
            var lines: [MetricLine] = []
            MetricLine.appendNoDataIfNeeded(&lines)
            return (plan, lines)
        }

        var lines: [MetricLine] = []
        if let window = usage["window"] as? [String: Any] {
            let minutes = ProviderParse.number(window["window_duration_mins"])
            lines.append(try percentLine(
                window, label: sessionLabel, periodMs: minutes.map { Int($0 * 60_000) }
            ))
        }
        if let weekly = usage["weekly"] as? [String: Any] {
            lines.append(try percentLine(weekly, label: weeklyLabel, periodMs: weekMs))
        }
        MetricLine.appendNoDataIfNeeded(&lines)
        return (plan, lines)
    }

    /// `used_percent` is an integer that may exceed 100 when over quota; the row clamps it for display.
    private static func percentLine(_ block: [String: Any], label: String, periodMs: Int?) throws -> MetricLine {
        guard let used = ProviderParse.number(block["used_percent"]), used >= 0 else {
            throw MuseCodeUsageError.invalidResponse
        }
        // `resets_at` is epoch seconds.
        let resetsAt = ProviderParse.number(block["resets_at"]).map { Date(timeIntervalSince1970: $0) }
        return .progress(
            label: label,
            used: used,
            limit: 100,
            format: .percent,
            resetsAt: resetsAt,
            periodDurationMs: periodMs
        )
    }
}

import AppKit
import SwiftUI

/// One metric on one line inside an account: label, meter, value, and reset time. The label column is
/// shared by every line on the dashboard and the other columns have fixed widths, so every bar in the
/// panel starts and ends at the same x. A reading without a limit (credits, a balance, a status) has no
/// bar; its value takes the bar's place, and the trailing column stays reserved for reset times.
///
/// Body text for the label and value, subheadline for the reset time. Nothing on a line acts on a click
/// except the Resets value ("● 2 available"), which opens the resets timeline, where a reset can be
/// claimed; its reset column counts down to the soonest expiry, tinted once that is within a week.
struct DashboardMetricLine: View {
    let data: WidgetData
    /// Width of the label column; `labelWidth(for:)` sizes it to the widest label on the dashboard.
    let labelWidth: CGFloat
    /// Claims a reset from the Resets line's timeline; `nil` keeps the timeline read-only.
    var resetClaim: ResetClaimService?

    /// A macOS list row and menu item are both 24 pt tall.
    static let height: CGFloat = 24
    static let columnSpacing: CGFloat = 8
    static let valueWidth: CGFloat = 40
    static let resetWidth: CGFloat = 52
    static let maxLabelWidth: CGFloat = 96

    var body: some View {
        Group {
            if data.resetsAt != nil || !data.expiriesAt.isEmpty {
                TimelineView(.periodic(from: .now, by: 30)) { _ in content }
            } else {
                content
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var content: some View {
        HStack(alignment: .firstTextBaseline, spacing: Self.columnSpacing) {
            Text(data.dashboardTitle)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)
            if data.isBounded {
                let state = data.meterState()
                UsageMeterBar(data: data, state: state)
                    // Centre the bar on the text's x-height rather than sitting it on the baseline.
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                value(state)
                    .frame(width: Self.valueWidth, alignment: .trailing)
            } else {
                unboundedValue
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(data.compactResetText() ?? "")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(data.resetColumnStyle())
                .lineLimit(1)
                .frame(width: Self.resetWidth, alignment: .trailing)
        }
        .font(.body)
        .frame(height: Self.height)
    }

    private func value(_ state: WidgetData.MeterState) -> some View {
        HStack(spacing: 2) {
            if state.severity == .critical {
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.meterFill(.critical))
            }
            Text(data.valueText)
                .fontWeight(.medium)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText())
        }
    }

    @ViewBuilder
    private var unboundedValue: some View {
        if data.showsResetExpiries {
            HStack(spacing: 5) {
                if let severity = data.expirySeverity() {
                    Circle()
                        .fill(Theme.meterFill(severity))
                        .frame(width: 6, height: 6)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                        .accessibilityLabel(Self.expiryAccessibilityLabel(severity))
                }
                Text(data.unboundedDetail)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .fixedSize()
            .rateLimitResetsPopover(data: data, claim: resetClaim)
        } else {
            Text(data.unboundedDetail)
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(.numericText())
        }
    }

    private static func expiryAccessibilityLabel(_ severity: WidgetData.MeterSeverity) -> String {
        switch severity {
        case .normal: "Reset credits expire in more than 7 days"
        case .warning: "A reset credit expires within 7 days"
        case .critical: "A reset credit expires within 48 hours"
        }
    }

    /// The label column fits the widest of `titles` in the body font, up to `maxLabelWidth`, past
    /// which a label truncates rather than squeezing every bar on the dashboard.
    static func labelWidth(for titles: some Sequence<String>) -> CGFloat {
        let font = NSFont.preferredFont(forTextStyle: .body)
        let widest = titles.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return min(ceil(widest) + 1, maxLabelWidth)
    }
}

extension WidgetData {
    /// The line's label: "Resets" for the Rate Limit Resets reading, which the dashboard's label column
    /// can't fit, and the reading's own title otherwise.
    var dashboardTitle: String { showsResetExpiries ? "Resets" : title }

    /// The reset column's reading: "1h 40m" as a countdown or "5:30 PM" as a clock time, following the
    /// global reset display mode. The Resets line reads the soonest expiry instead. `nil` when the line
    /// has no live reset.
    func compactResetText(now: Date = Date()) -> String? {
        let date: Date
        if showsResetExpiries {
            guard hasData, let soonest = expiriesAt.min() else { return nil }
            date = soonest
        } else {
            guard hasResetLabel(now: now), let resetsAt else { return nil }
            date = resetsAt
        }
        guard date.timeIntervalSince(now) > 0 else { return Formatters.imminent }
        if resetDisplayMode == .absolute {
            return Formatters.compactClock(date, now: now)
        }
        return Formatters.compactDuration(date.timeIntervalSince(now))
    }

    /// The reset column's color: secondary, or the soonest reset's expiry band once it's within a week
    /// (orange) or 48 hours (red).
    func resetColumnStyle(now: Date = Date()) -> AnyShapeStyle {
        switch expirySeverity(now: now) {
        case .critical: AnyShapeStyle(Color(nsColor: .systemRed))
        case .warning: AnyShapeStyle(Color(nsColor: .systemOrange))
        case .normal, nil: AnyShapeStyle(.secondary)
        }
    }
}

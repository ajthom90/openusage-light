import SwiftUI

/// One metric on one line inside an account: name, meter, value, and reset time. The columns have fixed
/// widths, so every bar in the panel starts and ends at the same x. A reading without a limit (credits,
/// a balance, a status) has no bar; its value takes the bar's place, and the trailing column stays
/// reserved for reset times.
///
/// The value flips the global Used/Left reading and the reset time flips countdown/clock time. No
/// tooltips: the line already says everything it knows.
///
/// The Resets line ("2 available") is a reading without a limit whose reset column counts down to the
/// soonest expiry, tinted once it's within a week. The whole line opens the resets timeline, where a
/// reset can be claimed.
struct DashboardMetricLine: View {
    let data: WidgetData
    var onToggleResetDisplay: (() -> Void)?
    var onToggleMeterStyle: (() -> Void)?
    /// Claims a reset from the Resets line's timeline; `nil` keeps the timeline read-only.
    var resetClaim: ResetClaimService?

    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular

    static let labelWidth: CGFloat = 72
    static let valueWidth: CGFloat = 44
    static let resetWidth: CGFloat = 56

    var body: some View {
        Group {
            if data.resetsAt != nil || !data.expiriesAt.isEmpty {
                TimelineView(.periodic(from: .now, by: 30)) { _ in line }
            } else {
                line
            }
        }
        .font(.system(size: density.supportingPointSize))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var line: some View {
        if data.showsResetExpiries {
            content.rateLimitResetsPopover(data: data, claim: resetClaim)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 8) {
            Text(data.dashboardTitle)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: Self.labelWidth, alignment: .leading)
            if data.isBounded {
                let state = data.meterState()
                UsageMeterBar(data: data, state: state)
                value(state)
                    .frame(width: Self.valueWidth, alignment: .trailing)
                reset
                    .frame(width: Self.resetWidth, alignment: .trailing)
            } else {
                Text(data.unboundedDetail)
                    .monospacedDigit()
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity, alignment: .leading)
                reset
                    .frame(width: Self.resetWidth, alignment: .trailing)
            }
        }
        .frame(height: density.metricLineHeight)
    }

    @ViewBuilder
    private func value(_ state: WidgetData.MeterState) -> some View {
        let label = HStack(spacing: 2) {
            if state.severity == .critical {
                Image(systemName: "flame.fill")
                    .font(.system(size: density.supportingPointSize - 3))
                    .foregroundStyle(Theme.meterFill(.critical))
            }
            Text(data.valueText)
                .fontWeight(.medium)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText())
        }
        if data.hasMeterStyleToggle, let onToggleMeterStyle {
            Button(action: onToggleMeterStyle) { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }

    @ViewBuilder
    private var reset: some View {
        if let text = data.compactResetText() {
            let label = Text(text)
                .foregroundStyle(data.resetColumnStyle())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            // The Resets line is one button (its timeline); every other line's reset time flips the
            // global countdown/clock reading.
            if let onToggleResetDisplay, !data.showsResetExpiries {
                Button(action: onToggleResetDisplay) { label }
                    .buttonStyle(.plain)
            } else {
                label
            }
        } else {
            Color.clear
        }
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

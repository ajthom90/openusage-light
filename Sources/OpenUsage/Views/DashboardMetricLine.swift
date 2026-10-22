import SwiftUI

/// One metric on one line inside an account: name, meter, value, and reset time. The columns have fixed
/// widths, so every bar in the panel starts and ends at the same x. A reading without a limit (credits,
/// a balance, a status) has no bar; its value takes the bar's place, and the trailing column stays
/// reserved for reset times.
///
/// The value flips the global Used/Left reading and the reset time flips countdown/clock time, each with
/// the full sentence in its tooltip.
struct DashboardMetricLine: View {
    let data: WidgetData
    var onToggleResetDisplay: (() -> Void)?
    var onToggleMeterStyle: (() -> Void)?

    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular

    static let labelWidth: CGFloat = 72
    static let valueWidth: CGFloat = 44
    static let resetWidth: CGFloat = 56

    var body: some View {
        Group {
            if data.resetsAt != nil {
                TimelineView(.periodic(from: .now, by: 30)) { _ in content }
            } else {
                content
            }
        }
        .frame(height: density.metricLineHeight)
        .font(.system(size: density.supportingPointSize))
    }

    private var content: some View {
        HStack(spacing: 8) {
            Text(data.title)
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
                    .hoverTooltip(data.unboundedValueTooltip)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear
                    .frame(width: Self.resetWidth)
            }
        }
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
        .hoverTooltip(valueTooltip(state))
        if data.hasMeterStyleToggle, let onToggleMeterStyle {
            Button(action: onToggleMeterStyle) { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }

    /// "71% left · 29% used", plus the pace projection when there is one.
    private func valueTooltip(_ state: WidgetData.MeterState) -> String {
        [data.boundedHeadline, data.meterStyleTooltip, state.tooltip].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private var reset: some View {
        if let text = data.compactResetText() {
            let label = Text(text)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .hoverTooltip(data.boundedTrailingText())
            if let onToggleResetDisplay {
                Button(action: onToggleResetDisplay) { label }
                    .buttonStyle(.plain)
            } else {
                label
            }
        } else {
            Color.clear.hoverTooltip(data.resetTooltip())
        }
    }
}

extension WidgetData {
    /// The reset column's reading: "1h 40m" as a countdown or "5:30 PM" as a clock time, following the
    /// global reset display mode. `nil` when the line has no live reset.
    func compactResetText(now: Date = Date()) -> String? {
        guard hasResetLabel(now: now), let resetsAt else { return nil }
        guard resetsAt.timeIntervalSince(now) > 0 else { return Formatters.imminent }
        if resetDisplayMode == .absolute {
            return Formatters.compactClock(resetsAt, now: now)
        }
        return Formatters.compactDuration(resetsAt.timeIntervalSince(now))
    }
}

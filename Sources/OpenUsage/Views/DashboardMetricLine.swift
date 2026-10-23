import SwiftUI

/// One metric on one line inside an account: label, meter, value, and reset time. The columns have fixed
/// widths, so every bar in the panel starts and ends at the same x. A reading without a limit (credits,
/// a balance, a status) has no bar; its value takes the bar's place, and the trailing column stays
/// reserved for reset times. The label and value columns fit every title and value at full size, so
/// neither truncates nor shrinks.
///
/// Nothing on a line reacts to the pointer. Used/Left and countdown/clock time are set in Settings →
/// Usage Display; right-click a line to star or hide it.
struct DashboardMetricLine: View {
    let data: WidgetData

    static let height: CGFloat = 20
    static let fontSize: CGFloat = 12
    static let columnSpacing: CGFloat = 8
    static let labelWidth: CGFloat = 86
    static let valueWidth: CGFloat = 52
    static let resetWidth: CGFloat = 56

    var body: some View {
        Group {
            if data.resetsAt != nil {
                TimelineView(.periodic(from: .now, by: 30)) { _ in content }
            } else {
                content
            }
        }
        .frame(height: Self.height)
        .font(.system(size: Self.fontSize))
        .accessibilityElement(children: .combine)
    }

    private var content: some View {
        HStack(spacing: Self.columnSpacing) {
            Text(data.title)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: Self.labelWidth, alignment: .leading)
            if data.isBounded {
                let state = data.meterState()
                UsageMeterBar(data: data, state: state)
                value(state)
                    .frame(width: Self.valueWidth, alignment: .trailing)
                Text(data.compactResetText() ?? "")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: Self.resetWidth, alignment: .trailing)
            } else {
                Text(data.unboundedDetail)
                    .monospacedDigit()
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear
                    .frame(width: Self.resetWidth)
            }
        }
    }

    private func value(_ state: WidgetData.MeterState) -> some View {
        HStack(spacing: 2) {
            if state.severity == .critical {
                Image(systemName: "flame.fill")
                    .font(.system(size: Self.fontSize - 3))
                    .foregroundStyle(Theme.severityColor(.critical))
            }
            Text(data.valueText)
                .fontWeight(.medium)
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(.numericText())
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

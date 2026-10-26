import SwiftUI

/// One metric on one row inside an account: label, bar, value and reset in fixed columns, so every bar
/// in the panel starts and ends at the same x. The label is secondary, the value medium in the
/// severity's colour once the bar is orange or red, the reset secondary. A reading without a limit (a
/// balance, a count, a status) has no bar: its value takes the bar's place. Nothing on a row reacts to
/// the pointer; the dashboard adds the resets popover around it.
struct DashboardMetricRow: View {
    let model: DashboardRowModel

    /// The row's type: 12 pt, under the 13 pt captions and names.
    static let font: Font = .callout

    var body: some View {
        HStack(spacing: DashboardGrid.columnGap) {
            Text(model.label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: DashboardGrid.labelWidth, alignment: .leading)
            switch model.mark {
            case .bar(let fill, let severity, let value, let reset):
                UsageMeterBar(fill: fill, severity: severity)
                Text(value)
                    .fontWeight(.medium)
                    .foregroundStyle(severity == .normal ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.severityColor(severity)))
                    .monospacedDigit()
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .frame(width: DashboardGrid.valueWidth, alignment: .trailing)
                Text(reset ?? "")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: DashboardGrid.resetWidth, alignment: .trailing)
            case .value(let text):
                Text(text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(Self.font)
        .padding(.horizontal, DashboardGrid.inset)
        .frame(height: DashboardGrid.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

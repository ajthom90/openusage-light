import SwiftUI

/// One metric on one row inside an account: label, bar, value and reset in fixed columns, so every bar
/// in the panel starts and ends at the same x. The label is secondary, the value medium in the
/// severity's colour once the bar is orange or red, the reset secondary. A reading without a limit (a
/// balance, a count, a status) has no bar: its figure takes the bar's place. Nothing on a row reacts to
/// the pointer; the dashboard wraps the Limit Resets row's figure in its hover through `figure`.
struct DashboardMetricRow: View {
    let model: DashboardRowModel
    /// Wraps a value row's figure, so the live dashboard can attach the resets hover to the figure alone.
    var figure: (AnyView) -> AnyView = { $0 }

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
                figure(AnyView(
                    Text(text)
                        .monospacedDigit()
                        .lineLimit(1)
                        .contentTransition(.numericText())
                        .fixedSize()
                ))
                Spacer(minLength: 0)
            }
        }
        .font(Self.font)
        .padding(.horizontal, DashboardGrid.inset)
        .frame(height: DashboardGrid.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

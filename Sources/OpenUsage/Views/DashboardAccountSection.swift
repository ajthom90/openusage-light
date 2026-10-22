import SwiftUI

/// One account as a row of its provider's grouped box, built on the native `DisclosureGroup`.
///
/// Collapsed, the row is a summary: the disclosure triangle, the account's name, plan, and reset
/// count, then its first metric (the one the user ordered first) as a small meter, value, and reset
/// time. Expanded, the summary keeps the name, plan, and resets, and every metric line shows below.
/// A click anywhere on the summary toggles it; the row takes the account's right-click menu.
struct DashboardAccountSection<Line: View>: View {
    let account: DashboardAccount
    var plan: String?
    var notice: String?
    var refreshing = false
    var staleness: StalenessHint?
    var resetClaim: ResetClaimService?
    var isExpanded = false
    var onToggleExpanded: (() -> Void)?
    /// Wraps the summary, so the dashboard can attach the account's drag gesture to it (and not to the
    /// metric lines, which have their own).
    var handle: (AnyView) -> AnyView = { $0 }
    @ViewBuilder var line: (DashboardLine) -> Line

    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    @Environment(AccountRenameStore.self) private var renaming: AccountRenameStore?
    @State private var isHovered = false

    var body: some View {
        DisclosureGroup(isExpanded: Binding(get: { isExpanded }, set: { _ in onToggleExpanded?() })) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(account.lines) { line($0) }
            }
            .padding(.top, 2)
            // Lines up the metric labels with the account name, past the disclosure triangle.
            .padding(.leading, Self.disclosureIndent)
        } label: {
            handle(AnyView(
                summary
                    // The native label stops short of the row's trailing edge; reach it, so the
                    // summary's numbers line up with the expanded lines' numbers.
                    .padding(.trailing, -Self.disclosureLabelTrailingGap)
                    .contentShape(Rectangle())
                    .onTapGesture { onToggleExpanded?() }
            ))
        }
        .padding(.horizontal, density.groupedRowInset)
        .padding(.vertical, density.groupedRowPadding)
        .background(rowFill)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityElement(children: .contain)
    }

    /// The width the native disclosure triangle and its gap take before the label, measured on macOS 27.
    static var disclosureIndent: CGFloat { 12 }
    /// The gap the native disclosure label leaves before the row's trailing edge, measured on macOS 27.
    static var disclosureLabelTrailingGap: CGFloat { 4 }

    /// Expanded rows sit on a slightly deeper fill, and the pointer lights a row the same way, so the
    /// open account and the one under the pointer both read at a glance.
    private var rowFill: some ShapeStyle {
        isExpanded || isHovered ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(.clear)
    }

    private var summary: some View {
        HStack(spacing: 6) {
            name
            if let plan {
                Text(plan)
                    .font(.system(size: density.supportingPointSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            if let resets = account.resets {
                ResetCountChip(data: resets, claim: resetClaim, compact: true)
                    .font(.system(size: density.supportingPointSize))
            }
            status
            Spacer(minLength: 6)
            if !isExpanded, let first = account.lines.first {
                DashboardHeadlineMetric(data: first.data)
            }
        }
        .frame(height: density.accountLineHeight)
    }

    @ViewBuilder
    private var name: some View {
        if let renaming, let edit = renaming.edit, edit.providerID == account.id {
            InlineRenameField(renaming: renaming, edit: edit)
                .font(.system(size: density.headerPointSize - 1, weight: .semibold))
                .fixedSize()
        } else {
            Text(account.name)
                .font(.system(size: density.headerPointSize - 1, weight: .semibold))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var status: some View {
        if refreshing {
            MotionAwareProgressView(controlSize: .mini)
                .accessibilityLabel("Refreshing")
        } else if let notice {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.notice)
                .hoverTooltip(notice)
                .accessibilityLabel(notice)
        } else if let staleness {
            Image(systemName: "clock")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .hoverTooltip(staleness.tooltip)
                .accessibilityLabel(staleness.tooltip)
        }
    }
}

/// A collapsed account's first metric, trailing its summary: a short meter, value, and reset time, in
/// the same value and reset columns as the expanded lines. Drops the meter when the row is too narrow.
struct DashboardHeadlineMetric: View {
    let data: WidgetData

    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular

    var body: some View {
        ViewThatFits(in: .horizontal) {
            content(meter: true)
            content(meter: false)
        }
        .font(.system(size: density.supportingPointSize))
        .accessibilityElement(children: .combine)
    }

    private func content(meter: Bool) -> some View {
        HStack(spacing: 8) {
            if data.isBounded {
                if meter {
                    UsageMeterBar(data: data, state: data.meterState())
                        .frame(width: 32)
                }
                Text(data.valueText)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .frame(width: DashboardMetricLine.valueWidth, alignment: .trailing)
                // Same value and reset columns as the expanded lines, so numbers line up row to row.
                Text(data.compactResetText() ?? "")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: DashboardMetricLine.resetWidth, alignment: .trailing)
            } else {
                Text(data.unboundedDetail)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .fixedSize()
    }
}

import SwiftUI

/// One account as a row of its provider's grouped box, built on `DisclosureGroup`.
///
/// Collapsed, the row is a summary: the disclosure chevron, the account's name and plan, then its first
/// metric (the one the user ordered first) as a small meter, value, and reset time. Expanded, the
/// summary keeps the name and plan, and every metric line shows below. The whole summary row is the
/// toggle: it lights under the pointer and takes the click over the same rect. The row takes the
/// account's right-click menu.
struct DashboardAccountSection<Line: View>: View {
    let account: DashboardAccount
    var plan: String?
    var notice: String?
    var refreshing = false
    var staleness: StalenessHint?
    var isExpanded = false
    var onToggleExpanded: (() -> Void)?
    /// Wraps the summary row, so the dashboard can attach the account's drag gesture to it (and not to
    /// the metric lines, which have their own).
    var handle: (AnyView) -> AnyView = { $0 }
    @ViewBuilder var line: (DashboardLine) -> Line

    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    @Environment(AccountRenameStore.self) private var renaming: AccountRenameStore?

    var body: some View {
        DisclosureGroup(isExpanded: Binding(get: { isExpanded }, set: { _ in onToggleExpanded?() })) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(account.lines) { line($0) }
            }
        } label: {
            summary
        }
        .disclosureGroupStyle(AccountDisclosureStyle(density: density, handle: handle))
        .accessibilityElement(children: .contain)
    }

    private var summary: some View {
        HStack(spacing: 6) {
            name
            if let plan {
                Text(plan)
                    .font(.system(size: density.supportingPointSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    // Below the name, above the trailing metric: a long plan truncates before the name.
                    .layoutPriority(1)
            }
            status
            Spacer(minLength: 0)
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
                .layoutPriority(2)
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

/// The account row's disclosure, laid out like a grouped Form's disclosure row: a chevron, then the
/// label, with the content below indented past the chevron. The summary row is one plain button across
/// the box's full width, padding included, so the click target is exactly the rect the hover lights.
private struct AccountDisclosureStyle: DisclosureGroupStyle {
    static let chevronWidth: CGFloat = 8
    static let chevronGap: CGFloat = 4
    /// The expanded lines indent past the chevron, so the metric labels line up with the account name.
    static var contentIndent: CGFloat { chevronWidth + chevronGap }

    let density: DensitySetting
    let handle: (AnyView) -> AnyView

    func makeBody(configuration: Configuration) -> some View {
        AccountDisclosure(configuration: configuration, density: density, handle: handle)
    }
}

private struct AccountDisclosure: View {
    let configuration: DisclosureGroupStyleConfiguration
    let density: DensitySetting
    let handle: (AnyView) -> AnyView

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            handle(AnyView(summaryRow))
            if configuration.isExpanded {
                configuration.content
                    .padding(.leading, density.groupedRowInset + AccountDisclosureStyle.contentIndent)
                    .padding(.trailing, density.groupedRowInset)
                    .padding(.bottom, density.groupedRowPadding)
            }
        }
    }

    private var summaryRow: some View {
        Button { configuration.isExpanded.toggle() } label: {
            HStack(spacing: AccountDisclosureStyle.chevronGap) {
                Image(systemName: "chevron.right")
                    .font(.system(size: density.supportingPointSize - 1, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                    .frame(width: AccountDisclosureStyle.chevronWidth)
                configuration.label
            }
            .padding(.horizontal, density.groupedRowInset)
            .padding(.vertical, density.groupedRowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
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
                        .frame(width: 28)
                }
                Text(data.valueText)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .frame(width: DashboardMetricLine.valueWidth, alignment: .trailing)
            } else {
                Text(data.unboundedDetail)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            // Same reset column as the expanded lines, so numbers line up row to row.
            Text(data.compactResetText() ?? "")
                .foregroundStyle(data.resetColumnStyle())
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: DashboardMetricLine.resetWidth, alignment: .trailing)
        }
        .fixedSize()
    }
}

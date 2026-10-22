import SwiftUI

/// One account in its provider's grouped box: a name line (the name, its plan right after it, and a
/// status icon) over every metric line that has data, in the user's order. The account isn't a control:
/// the only thing inside it that acts on a click is the Resets value. The name line drags the account;
/// right-click it for the account's menu, or a metric line for the metric's.
struct DashboardAccountSection<Line: View>: View {
    let account: DashboardAccount
    var plan: String?
    var notice: String?
    var refreshing = false
    var staleness: StalenessHint?
    /// Wraps the name line, so the dashboard can attach the account's drag gesture to it. Metric lines
    /// drag themselves.
    var handle: (AnyView) -> AnyView = { $0 }
    @ViewBuilder var line: (DashboardLine) -> Line

    @Environment(AccountRenameStore.self) private var renaming: AccountRenameStore?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            handle(AnyView(header))
            ForEach(account.lines) { line($0) }
        }
        .padding(.horizontal, DashboardBox.textInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            name
            if let plan {
                Text(plan)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    // Below the name: a long plan truncates before the name does.
                    .layoutPriority(1)
            }
            status
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: DashboardMetricLine.height)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var name: some View {
        if let renaming, let edit = renaming.edit, edit.providerID == account.id {
            InlineRenameField(renaming: renaming, edit: edit)
                .font(.body.weight(.semibold))
                .fixedSize()
        } else {
            Text(account.name)
                .font(.body.weight(.semibold))
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
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.notice)
                .hoverTooltip(notice)
                .accessibilityLabel(notice)
        } else if let staleness {
            Image(systemName: "clock")
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
                .hoverTooltip(staleness.tooltip)
                .accessibilityLabel(staleness.tooltip)
        }
    }
}

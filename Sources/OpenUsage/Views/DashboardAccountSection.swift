import SwiftUI

/// One account as a block of its provider's grouped box: a header line (disclosure triangle, name, and
/// the plan once expanded) over its metric lines. Collapsed, the block shows the account's first two
/// metrics with a limit (`DashboardAccount.summaryLines`); expanded, every metric.
///
/// The whole block is one button, like a menu item: it lights under the pointer, and a click anywhere in
/// it expands or collapses the account. The Resets value is the one control
/// inside it, with its own highlight and popover. An account with nothing more to show has no
/// triangle and isn't a button. Right-click the block for the account's menu, or a line for the metric's.
struct DashboardAccountSection<Line: View>: View {
    let account: DashboardAccount
    var plan: String?
    var notice: String?
    var refreshing = false
    var staleness: StalenessHint?
    var isExpanded = false
    var onToggleExpanded: (() -> Void)?
    /// Wraps each part of the block that drags the account: the header line, and the summary lines while
    /// collapsed. Expanded metric lines drag themselves instead.
    var handle: (AnyView) -> AnyView = { $0 }
    @ViewBuilder var line: (DashboardLine) -> Line

    @Environment(AccountRenameStore.self) private var renaming: AccountRenameStore?

    /// Width of the disclosure triangle's column. The metric lines indent by it, so their labels line up
    /// with the account name the way a grouped form indents a disclosure group's content.
    static var indent: CGFloat { 12 }

    var body: some View {
        if account.isExpandable(plan: plan) {
            Button { onToggleExpanded?() } label: { content(expandable: true) }
                .buttonStyle(AccountBlockStyle())
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        } else {
            content(expandable: false)
        }
    }

    private func content(expandable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            handle(AnyView(header(expandable: expandable)))
            ForEach(isExpanded ? account.lines : account.summaryLines) { item in
                if isExpanded {
                    line(item)
                } else {
                    handle(AnyView(line(item)))
                }
            }
            .padding(.leading, Self.indent)
        }
        .padding(.horizontal, DashboardBox.textInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func header(expandable: Bool) -> some View {
        HStack(spacing: 0) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: Self.indent, alignment: .leading)
                .opacity(expandable ? 1 : 0)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                name
                if isExpanded, let plan {
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
            Spacer(minLength: 0)
        }
        .frame(height: DashboardMetricLine.height)
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

/// The account block's highlight: a rounded fill inset from the grouped box, lit while the pointer is
/// over the block, the way a menu item lights.
private struct AccountBlockStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AccountBlockHighlight(label: configuration.label)
    }
}

private struct AccountBlockHighlight: View {
    let label: ButtonStyleConfiguration.Label

    @State private var isHovered = false

    var body: some View {
        label
            .background {
                RoundedRectangle(cornerRadius: DashboardBox.highlightCornerRadius, style: .continuous)
                    .fill(.fill.quaternary)
                    .padding(.horizontal, DashboardBox.highlightInset)
                    .opacity(isHovered ? 1 : 0)
            }
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.1), value: isHovered)
    }
}

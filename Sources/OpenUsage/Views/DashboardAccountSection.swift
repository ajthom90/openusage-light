import SwiftUI

/// One account inside its provider's card: the account line (name and status on the left; plan and
/// reset count as plain text on the right, "Max 5x · ↺ 2 resets") over its metric lines. The whole
/// block is the account's target: the pointer lights it the way a menu item lights, and it takes the
/// account's right-click menu.
struct DashboardAccountSection<Line: View>: View {
    let account: DashboardAccount
    var plan: String?
    var notice: String?
    var refreshing = false
    var staleness: StalenessHint?
    var resetClaim: ResetClaimService?
    /// Wraps the account line, so the dashboard can attach the account's drag gesture to it (and not to
    /// the metric lines, which have their own).
    var handle: (AnyView) -> AnyView = { $0 }
    @ViewBuilder var line: (DashboardLine) -> Line

    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    @Environment(AccountRenameStore.self) private var renaming: AccountRenameStore?
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            handle(AnyView(accountLine.contentShape(Rectangle())))
            ForEach(account.lines) { line($0) }
        }
        .padding(.vertical, highlightOutset)
        .background {
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius - density.accountHighlightInset, style: .continuous)
                .fill(.fill.tertiary)
                .padding(.horizontal, -highlightOutset)
                .opacity(isHovered ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
    }

    /// How far the hover highlight reaches past the content toward the popover edge: all the way to one
    /// highlight inset short of it. Also the block's vertical padding, so the highlight wraps the
    /// content evenly on every side.
    private var highlightOutset: CGFloat { density.panelPadding - density.accountHighlightInset }

    private var accountLine: some View {
        HStack(spacing: 6) {
            name
            status
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                if let plan {
                    Text(plan)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let resets = account.resets {
                    if plan != nil {
                        Text("·").foregroundStyle(.tertiary)
                    }
                    ResetCountChip(data: resets, claim: resetClaim)
                }
            }
            .font(.system(size: density.supportingPointSize))
            .layoutPriority(1)
        }
        .frame(height: density.accountLineHeight)
    }

    @ViewBuilder
    private var name: some View {
        if let renaming, let edit = renaming.edit, edit.providerID == account.id {
            InlineRenameField(renaming: renaming, edit: edit)
                .font(.system(size: density.headerPointSize - 1, weight: .medium))
                .fixedSize()
        } else {
            Text(account.name)
                .font(.system(size: density.headerPointSize - 1, weight: .medium))
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

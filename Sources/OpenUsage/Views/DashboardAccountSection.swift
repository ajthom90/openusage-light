import SwiftUI

/// One account inside its provider's card: the account line (name, status, reset count, plan) over its
/// metric lines. Shown and extra lines share one `ForEach`, so a line dragged between them keeps its
/// identity and its drag gesture. The whole block is the account's target: the pointer lights it the
/// way a menu item lights, it takes the account's right-click menu, and when the account has lines to
/// reveal, a click shows or hides them.
struct DashboardAccountSection<Line: View>: View {
    let account: DashboardAccount
    var plan: String?
    var notice: String?
    var refreshing = false
    var staleness: StalenessHint?
    var isExpanded = false
    var resetClaim: ResetClaimService?
    var onToggleExpanded: (() -> Void)?
    @ViewBuilder var line: (DashboardLine) -> Line

    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    @Environment(AccountRenameStore.self) private var renaming: AccountRenameStore?
    @State private var isHovered = false

    private var canExpand: Bool { onToggleExpanded != nil && !account.extraLines.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            accountLine
            ForEach(account.lines + (isExpanded ? account.extraLines : [])) { line($0) }
        }
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.fill.tertiary)
                .padding(.horizontal, -Self.highlightOutset)
                .opacity(isHovered ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            if canExpand { onToggleExpanded?() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: isExpanded ? "Show Less" : "Show More") {
            if canExpand { onToggleExpanded?() }
        }
    }

    /// How far the hover highlight reaches past the content edge, toward the card edge.
    static var highlightOutset: CGFloat { 6 }

    private var accountLine: some View {
        HStack(spacing: 6) {
            name
            status
            Spacer(minLength: 8)
            if let resets = account.resets {
                ResetCountChip(data: resets, claim: resetClaim)
            }
            if let plan {
                PlanChip(plan: plan)
                    .layoutPriority(1)
            }
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

/// The account's plan as a small capsule at the trailing edge of the account line.
struct PlanChip: View {
    let plan: String

    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular

    var body: some View {
        Text(plan)
            .font(.system(size: density.planBadgePointSize, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(Capsule().fill(.fill.tertiary))
    }
}

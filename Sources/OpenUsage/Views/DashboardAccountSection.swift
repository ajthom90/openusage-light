import SwiftUI

/// One account inside its provider's card: the account line (name, badges) over every metric line that
/// has data, in the user's order. On a card with one account the provider's header carries the name and
/// badges, and the account line is left out (`showsAccountLine`). The ↺ tag is the one part that reacts to hover
/// or a click: it opens the resets timeline. A double-click on the name renames the account.
/// Right-click the account for its menu; the name line drags it.
struct DashboardAccountSection<Line: View>: View {
    let account: DashboardAccount
    var badges = AccountBadges()
    var showsAccountLine = true
    /// Wraps the account line, so the dashboard can attach the account's drag gesture to it. Metric
    /// lines drag themselves.
    var handle: (AnyView) -> AnyView = { $0 }
    @ViewBuilder var line: (DashboardLine) -> Line

    /// Height of the account line.
    static var lineHeight: CGFloat { 24 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsAccountLine {
                handle(AnyView(accountLine))
            }
            ForEach(account.lines) { line($0) }
        }
        .padding(.horizontal, DashboardBox.inset)
        .padding(.vertical, DashboardBox.accountPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    var accountLine: some View {
        HStack(spacing: 6) {
            name
            badges.status
            Spacer(minLength: 8)
            badges.tags
        }
        .frame(height: Self.lineHeight)
        .contentShape(Rectangle())
    }

    var name: AccountName {
        AccountName(account: account, font: .system(size: 13, weight: .medium))
    }
}

/// An account's name on the dashboard, on its account line or in a one-account card's header. A
/// double-click opens the inline rename in its place, the same as the right-click Rename.
struct AccountName: View {
    let account: DashboardAccount
    let font: Font

    @Environment(AccountRenameStore.self) private var renaming: AccountRenameStore?

    var body: some View {
        if let renaming, let edit = renaming.edit, edit.providerID == account.id {
            InlineRenameField(renaming: renaming, edit: edit)
                .font(font)
                .fixedSize()
        } else {
            Text(account.name)
                .font(font)
                .lineLimit(1)
                .truncationMode(.middle)
                .onTapGesture(count: 2) { renaming?.begin(account.id) }
        }
    }
}

/// What sits beside an account's name: its refresh state, then at the trailing edge the ↺ resets tag
/// and the plan tag. On a card with one account they sit in the provider's header instead.
@MainActor
struct AccountBadges {
    /// The account's Rate Limit Resets reading (`DashboardAccount.resets`).
    var resets: WidgetData?
    var plan: String?
    var notice: String?
    var refreshing = false
    var staleness: StalenessHint?
    var resetClaim: ResetClaimService?

    /// The refresh state. A warning or stale icon explains itself in the right-click menu.
    @ViewBuilder
    var status: some View {
        if refreshing {
            MotionAwareProgressView(controlSize: .mini)
                .accessibilityLabel("Refreshing")
        } else if let notice {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.notice)
                .accessibilityLabel(notice)
        } else if let staleness {
            Image(systemName: "clock")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .accessibilityLabel(staleness.tooltip)
        }
    }

    @ViewBuilder
    var tags: some View {
        if let resets {
            ResetCountChip(data: resets, claim: resetClaim)
        }
        if let plan {
            PlanTag(plan: plan)
                .layoutPriority(1)
        }
    }
}

/// The account's plan as a grey capsule at the trailing edge of the account line or one-account header.
struct PlanTag: View {
    let plan: String

    var body: some View {
        Text(plan)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(Capsule().fill(.fill.tertiary))
    }
}

import SwiftUI

/// One provider on the dashboard: its header above its card. The header names the provider — and its
/// account, when it has one with a name of its own — in Title 3, with the plan right-aligned before the
/// 16 pt logo at the end of the line, which sits in line with the bars below. The card holds the
/// provider's accounts, separated by space alone: each a caption (when there are several) over one row
/// per metric. Static: the dashboard adds hover, menus and drags around it, and the share image draws it
/// as it is.
struct DashboardProviderSection<Trailing: View, Account: View>: View {
    let family: DashboardFamily
    /// The plan of an account, by its id.
    var plans: [String: String] = [:]
    /// The sole account's status glyph, shown in the header after its name.
    var status: AccountStatus = AccountStatus()
    /// Wraps the header, so the dashboard can attach the provider's drag gesture to it.
    var handle: (AnyView) -> AnyView = { $0 }
    /// What ends the header line: the provider's logo, or the copy button in its place.
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var account: (DashboardAccount) -> Account

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardGrid.headerGap) {
            handle(AnyView(header))
            VStack(alignment: .leading, spacing: DashboardGrid.accountSpacing) {
                ForEach(family.accounts) { account($0) }
            }
            .padding(DashboardGrid.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    var header: some View {
        DashboardProviderHeader(
            family: family,
            plan: family.soleAccount.flatMap { plans[$0.id] },
            status: status,
            trailing: trailing
        )
    }
}

/// The line above a provider's card. The title truncates at its end and stops at least 8 pt before the
/// plan, which is never cut; the plan sits 8 pt before the logo, both centred on the line.
struct DashboardProviderHeader<Trailing: View>: View {
    let family: DashboardFamily
    var plan: String?
    var status = AccountStatus()
    @ViewBuilder var trailing: () -> Trailing

    private static var titleFont: Font { .title3.weight(.semibold) }

    var body: some View {
        HStack(spacing: 0) {
            if let account = family.namedSoleAccount {
                Text("\(family.provider.displayName) — ")
                    .font(Self.titleFont)
                    .fixedSize()
                AccountName(account: account, font: Self.titleFont)
            } else {
                Text(family.provider.displayName)
                    .font(Self.titleFont)
                    .lineLimit(1)
            }
            status.glyph.padding(.leading, Theme.Spacing.s)
            Spacer(minLength: DashboardGrid.columnGap)
            if let plan {
                Text(plan)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.trailing, DashboardGrid.columnGap)
            }
            trailing()
                .frame(width: DashboardGrid.iconSize, height: DashboardGrid.iconSize)
        }
        .padding(.horizontal, DashboardGrid.cardPadding + DashboardGrid.inset)
        .frame(height: DashboardGrid.headerHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// An account's caption inside a card with several accounts: its name in Subheadline semibold and its
/// plan after it, both secondary. The name truncates (an email keeps its domain) and the plan never does.
struct DashboardAccountCaption: View {
    let account: DashboardAccount
    var plan: String?
    var status = AccountStatus()

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            AccountName(account: account, font: .subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            status.glyph
            if let plan {
                Text(plan)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DashboardGrid.inset)
        .frame(height: DashboardGrid.captionHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// An account's name on the dashboard, in its provider's header or on its caption. A double-click opens
/// the inline rename in its place, the same as the right-click Rename.
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
                .truncationMode(account.provider.isNamedByEmail ? .middle : .tail)
                .onTapGesture(count: 2) { renaming?.begin(account.id) }
        }
    }
}

/// An account's refresh state, after its name: a spinner while it refreshes, a warning when the refresh
/// failed, a clock when its reading is stale. Nothing while all is well. The right-click menu explains a
/// warning or clock.
struct AccountStatus {
    var refreshing = false
    var notice: String?
    var staleness: StalenessHint?

    @ViewBuilder
    var glyph: some View {
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
}

/// An account's caption (in a card with several accounts) over its rows, at rest: what the share image
/// and the drag previews draw.
struct DashboardAccountRows: View {
    let account: DashboardAccount
    var plan: String?
    let labelWidth: CGFloat
    var showsCaption = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsCaption {
                DashboardAccountCaption(account: account, plan: plan)
            }
            ForEach(account.lines) { line in
                DashboardMetricRow(model: line.data.dashboardRow(), labelWidth: labelWidth)
            }
        }
    }
}

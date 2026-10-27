import SwiftUI

/// One provider on the dashboard: its header above its card. One rule for every card: a provider with
/// one account puts that account on the header — its name, its status glyph, its plan right-aligned
/// before the logo at the end of the line, where the rows' reset column ends — and its rows alone in
/// the card; a provider with several accounts puts its own name on the header and each account inside
/// the card as a caption, name and plan, over its rows. The logo says which provider it is, so the
/// header never spells "Provider — name". Static but for the status glyph's tooltip: the dashboard
/// adds hover, menus and drags around it, and the share image draws it as it is.
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
    /// An account's block in the card: with its caption when `captioned`, or its rows alone.
    @ViewBuilder var account: (DashboardAccount, _ captioned: Bool) -> Account

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardGrid.headerGap) {
            handle(AnyView(header))
            VStack(alignment: .leading, spacing: DashboardGrid.accountSpacing) {
                ForEach(family.accounts) { account($0, family.soleAccount == nil) }
            }
            .padding(DashboardGrid.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    var header: some View {
        DashboardProviderHeader(
            provider: family.provider,
            account: family.soleAccount,
            plan: family.soleAccount.flatMap { plans[$0.id] },
            status: status,
            trailing: trailing
        )
    }
}

/// The line above a provider's card: the sole account's name, or the provider's over several accounts,
/// the plan 8 pt before the logo, both centred on the line, nothing cut.
struct DashboardProviderHeader<Trailing: View>: View {
    let provider: Provider
    /// The sole account the header names, or `nil` for the provider over several accounts.
    var account: DashboardAccount?
    var plan: String?
    var status = AccountStatus()
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            if let account {
                AccountName(account: account, font: DashboardGrid.headerFont)
            } else {
                Text(provider.displayName)
                    .font(DashboardGrid.headerFont)
                    .lineLimit(1)
            }
            status.glyph.padding(.leading, Theme.Spacing.s)
            Spacer(minLength: DashboardGrid.columnGap)
            if let plan {
                Text(plan)
                    .font(DashboardGrid.planFont)
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

/// An account's caption inside a card with several accounts: its name in Subheadline semibold at the
/// left and its plan as plain Subheadline at the right, both secondary — never a badge. The name
/// truncates (an email keeps its domain) and the plan never does.
struct DashboardAccountCaption: View {
    let account: DashboardAccount
    var plan: String?
    var status = AccountStatus()

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            AccountName(account: account, font: DashboardGrid.captionFont)
                .foregroundStyle(.secondary)
            status.glyph
            Spacer(minLength: DashboardGrid.columnGap)
            if let plan {
                Text(plan)
                    .font(DashboardGrid.planFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
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
/// failed, a clock when its reading is stale. Nothing while all is well. A warning or clock explains
/// itself on hover, as the right-click menu does; the spinner says nothing.
struct AccountStatus {
    var refreshing = false
    var notice: String?
    var staleness: StalenessHint?

    @MainActor @ViewBuilder
    var glyph: some View {
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

/// An account's caption over its rows, at rest, or its rows alone when it is the card's sole account
/// and the header names it: what the share image and the drag previews draw.
struct DashboardAccountRows: View {
    let account: DashboardAccount
    var plan: String?
    var captioned = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if captioned {
                DashboardAccountCaption(account: account, plan: plan)
            }
            ForEach(account.lines) { line in
                DashboardMetricRow(model: line.data.dashboardRow())
            }
        }
    }
}

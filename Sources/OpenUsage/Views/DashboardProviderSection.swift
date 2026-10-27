import SwiftUI

/// One provider on the dashboard: its header above its card. The header names the provider — and its
/// account, when it has one with a name of its own that fits the line — in Headline, with the plan
/// right-aligned before the logo at the end of the line, which ends where the rows' reset column does. The card holds the provider's accounts, separated by space alone: each a caption over one row
/// per metric, the caption left out when the header names the account. Nothing on the line is ever
/// cut or shrunk: a sole account whose "Provider — name" and plan don't fit beside the logo reads as a
/// card of several accounts would, the provider alone above, the name and plan on the caption. Static:
/// the dashboard adds hover, menus and drags around it, and the share image draws it as it is.
struct DashboardProviderSection<Trailing: View, Account: View>: View {
    let family: DashboardFamily
    /// The plan of an account, by its id.
    var plans: [String: String] = [:]
    /// The sole account's status glyph, shown in the header after its name while the header names it.
    var status: AccountStatus = AccountStatus()
    /// The line's width, which decides whether the header can name the account.
    var width: CGFloat = DashboardGrid.cardWidth
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
                ForEach(family.accounts) { account($0, headerAccount == nil) }
            }
            .padding(DashboardGrid.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    var header: some View {
        let account = headerAccount
        return DashboardProviderHeader(
            provider: family.provider,
            account: account?.name == family.provider.displayName ? nil : account,
            plan: account.flatMap { plans[$0.id] },
            status: account == nil ? AccountStatus() : status,
            trailing: trailing
        )
    }

    /// The sole account whose plan and status the header carries, and whose name it reads when the
    /// account has one of its own that fits the line. An account named like its provider reads as the
    /// provider alone; one whose name doesn't fit, or one of several, is captioned in the card instead.
    var headerAccount: DashboardAccount? {
        guard let account = family.soleAccount else { return nil }
        if account.name == family.provider.displayName { return account }
        return DashboardHeaderLine.fits(provider: family.provider, name: account.name, plan: plans[account.id], width: width) ? account : nil
    }
}

/// What fits on the header line, measured with the line's own type.
enum DashboardHeaderLine {
    /// Whether "Provider — name" fits the line at `width` beside the plan and the logo. Room is kept for
    /// the status glyph, so a refresh spinner never flips the header, and for the point or two SwiftUI's
    /// text can run past AppKit's measure.
    static func fits(provider: Provider, name: String, plan: String?, width: CGFloat) -> Bool {
        func measure(_ text: String, _ font: NSFont) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
        }
        let insets = 2 * (DashboardGrid.cardPadding + DashboardGrid.inset)
        let glyph = Theme.Spacing.s + 12
        let logo = DashboardGrid.columnGap + DashboardGrid.iconSize
        let planRoom = plan.map { measure($0, DashboardGrid.planNSFont) + DashboardGrid.columnGap } ?? 0
        let slack: CGFloat = 2
        return measure("\(provider.displayName) — \(name)", DashboardGrid.headerNSFont) <= width - insets - glyph - logo - planRoom - slack
    }
}

/// The line above a provider's card: the provider, or "Provider — account" when the account's name fits
/// (`DashboardHeaderLine.fits`), the plan 8 pt before the logo, both centred on the line, nothing cut.
struct DashboardProviderHeader<Trailing: View>: View {
    let provider: Provider
    /// The account named after the provider, or `nil` for the provider alone.
    var account: DashboardAccount?
    var plan: String?
    var status = AccountStatus()
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            if let account {
                Text("\(provider.displayName) — ")
                    .font(DashboardGrid.headerFont)
                    .fixedSize()
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

/// An account's caption over its rows, at rest, or its rows alone when the header names it: what the
/// share image and the drag previews draw.
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

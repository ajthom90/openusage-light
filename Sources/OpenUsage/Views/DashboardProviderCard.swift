import SwiftUI

/// One provider's card on the dashboard: the provider's mark and name inside the card, then each of its
/// accounts, separated by space alone. The mark sits flush with the account names and metric labels
/// below it. On a card with one account the header shows that account instead: its name (which a
/// double-click renames) and status beside the mark, its ↺ and plan tags at the trailing edge, and the
/// account shows no name line of its own. Right-click the card for its menu.
struct DashboardProviderCard<Account: View>: View {
    let family: DashboardFamily
    /// The badges of a card's only account, shown in its header.
    var badges: (DashboardAccount) -> AccountBadges = { _ in AccountBadges() }
    /// Wraps the header, so the dashboard can attach the card's drag gesture to it.
    var handle: (AnyView) -> AnyView = { $0 }
    @ViewBuilder var account: (DashboardAccount) -> Account

    private static var titleFont: Font { .system(size: 14, weight: .semibold) }

    /// Party easter egg: pulse the provider mark.
    @Environment(\.popoverPartyMode) private var partyMode

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardBox.headerGap) {
            handle(AnyView(header))
            VStack(alignment: .leading, spacing: DashboardBox.accountSpacing) {
                ForEach(family.accounts) { account($0) }
            }
        }
        .padding(.top, DashboardBox.topPadding)
        .padding(.bottom, DashboardBox.bottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    var header: some View {
        HStack(spacing: 6) {
            ProviderIcon(source: family.provider.icon, inset: 0.04)
                .frame(width: 16, height: 16)
                .partyPulse(partyMode)
            if let account = family.soleAccount {
                let badges = badges(account)
                AccountName(account: account, font: Self.titleFont)
                badges.status
                Spacer(minLength: 8)
                badges.tags
            } else {
                Text(family.provider.displayName)
                    .font(Self.titleFont)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DashboardBox.inset)
        .contentShape(Rectangle())
    }
}

/// Where things sit inside and between provider cards. Everything is `inset` in from the card's sides,
/// so the provider's mark lines up with the account names and metric labels below it. The rows keep
/// their full height (24 pt name lines, 20 pt metric lines) and the card's own padding stays small:
/// 10 pt above the header and below the last row, 6 pt from the header to the first row, 10 pt between
/// two accounts, and 8 pt between two cards.
enum DashboardBox {
    static let inset = Theme.Spacing.xl
    /// Between two provider cards.
    static let cardSpacing = Theme.Spacing.m
    /// Above the header.
    static let topPadding = Theme.Spacing.l
    /// Between the header and the first account, on top of the account's own padding.
    static let headerGap = Theme.Spacing.xs
    /// Above and below each account's content.
    static let accountPadding = Theme.Spacing.xxs
    /// Between two accounts, on top of their own padding.
    static let accountSpacing = Theme.Spacing.s
    /// Below the last account, on top of its own padding.
    static let bottomPadding = Theme.Spacing.m
}

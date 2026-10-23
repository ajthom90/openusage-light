import SwiftUI

/// One provider's section on the dashboard: the provider's mark and name, then each of its accounts,
/// separated by space alone. Sections sit straight on the panel, edge to edge, with a hairline between
/// two of them (`DashboardSeparator`). The mark sits flush with the account names and metric labels
/// below it. On a section with one account the header shows that account instead: its name (which a
/// double-click renames) and status beside the mark, its ↺ and plan tags at the trailing edge, and the
/// account shows no name line of its own. Right-click the section for its menu.
struct DashboardProviderSection<Account: View>: View {
    let family: DashboardFamily
    /// The badges of a section's only account, shown in its header.
    var badges: (DashboardAccount) -> AccountBadges = { _ in AccountBadges() }
    /// Wraps the header, so the dashboard can attach the section's drag gesture to it.
    var handle: (AnyView) -> AnyView = { $0 }
    @ViewBuilder var account: (DashboardAccount) -> Account

    private static var titleFont: Font { .system(size: 14, weight: .semibold) }

    /// Party easter egg: pulse the provider mark.
    @Environment(\.popoverPartyMode) private var partyMode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            handle(AnyView(header))
            VStack(alignment: .leading, spacing: DashboardSpacing.accountSpacing) {
                ForEach(family.accounts) { account($0) }
            }
        }
        .padding(.vertical, DashboardSpacing.sectionPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// As tall as an account's name line, which it stands in for on a one-account section, so the
    /// header and the last row leave about the same slack on either side of the separator.
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
        .frame(height: DashboardAccountSection<EmptyView>.lineHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DashboardSpacing.inset)
        .contentShape(Rectangle())
    }
}

/// The line between two provider sections: one device pixel of the system separator colour, across
/// the panel's full width.
struct DashboardSeparator: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1 / displayScale)
            .frame(maxWidth: .infinity)
    }
}

/// Where things sit on the dashboard. The mark, names, labels, and trailing column all sit `inset`
/// from the panel's edge. Vertically it is one 8 pt step: above each header, below each section's last
/// row (so the separator between two sections is centred in 16 pt), and between two accounts. The list
/// adds `listPadding`, so the first header and the last row sit the panel's 14 pt margin from its ends.
enum DashboardSpacing {
    static let inset = Theme.Spacing.xxl
    /// Above a section's header and below its last row.
    static let sectionPadding = Theme.Spacing.m
    /// Between two accounts in one section.
    static let accountSpacing = Theme.Spacing.m
    /// Above the first section and below the last, on top of their own padding.
    static let listPadding = Theme.Spacing.s
}

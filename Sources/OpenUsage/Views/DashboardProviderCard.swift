import SwiftUI

/// One provider's card on the dashboard: the provider's mark and name inside the card, then each of its
/// accounts, separated by space alone. The mark sits flush with the account names and metric labels
/// below it. Nothing reacts to the pointer; right-click the card for the provider's menu.
struct DashboardProviderCard<Account: View>: View {
    let family: DashboardFamily
    /// Wraps the header, so the dashboard can attach the card's drag gesture to it.
    var handle: (AnyView) -> AnyView = { $0 }
    @ViewBuilder var account: (DashboardAccount) -> Account

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

    private var header: some View {
        HStack(spacing: 6) {
            ProviderIcon(source: family.provider.icon, inset: 0.04)
                .frame(width: 16, height: 16)
                .partyPulse(partyMode)
            Text(family.provider.displayName)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DashboardBox.inset)
        .contentShape(Rectangle())
    }
}

/// Where things sit inside a provider's card. Everything is `inset` in from the card's sides, so the
/// provider's mark lines up with the account names and metric labels below it.
enum DashboardBox {
    static let inset: CGFloat = 14
    /// Above the header.
    static let topPadding: CGFloat = 12
    /// Between the header and the first account, on top of the account's own padding.
    static let headerGap: CGFloat = 4
    /// Above and below each account's content.
    static let accountPadding: CGFloat = 4
    /// Between two accounts, on top of their own padding.
    static let accountSpacing: CGFloat = 6
    /// Below the last account, on top of its own padding.
    static let bottomPadding: CGFloat = 8
}

import SwiftUI

/// One provider's card on the dashboard: the provider's mark and name, then each of its accounts,
/// separated by space alone. The mark sits flush with the account names and metric labels below it.
struct DashboardProviderCard<Account: View>: View {
    let family: DashboardFamily
    @ViewBuilder var account: (DashboardAccount) -> Account

    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    /// Party easter egg: pulse the provider mark.
    @Environment(\.popoverPartyMode) private var partyMode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ProviderIcon(source: family.provider.icon, inset: 0.04)
                    .frame(width: density.headerIconSize, height: density.headerIconSize)
                    .partyPulse(partyMode)
                Text(family.provider.displayName)
                    .font(.system(size: density.headerPointSize, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.bottom, 4)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(family.accounts) { account($0) }
            }
        }
        .padding(.horizontal, density.cardPadding)
        .padding(.top, density.cardPadding - 2)
        .padding(.bottom, density.cardPadding - 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

import AppKit
import SwiftUI

/// One provider's card on the dashboard: the provider's mark and name, then each of its accounts,
/// separated by space alone. The mark sits flush with the account names and metric labels below it.
/// Hovering the card reveals the provider's quick links (Status, Dashboard) at the header's trailing
/// edge, as small text links that open in the browser.
struct DashboardProviderCard<Account: View>: View {
    let family: DashboardFamily
    @ViewBuilder var account: (DashboardAccount) -> Account

    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    /// Party easter egg: pulse the provider mark.
    @Environment(\.popoverPartyMode) private var partyMode
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ProviderIcon(source: family.provider.icon, inset: 0.04)
                    .frame(width: density.headerIconSize, height: density.headerIconSize)
                    .partyPulse(partyMode)
                Text(family.provider.displayName)
                    .font(.system(size: density.headerPointSize, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                ProviderHeaderLinks(links: family.provider.visibleLinks)
                    .opacity(isHovered ? 1 : 0)
                    .allowsHitTesting(isHovered)
            }
            .padding(.horizontal, density.cardPadding)
            .padding(.top, density.cardPadding)
            .padding(.bottom, density.headerBottomPadding)
            // Accounts stack edge to edge: each carries its own vertical padding, so its hover
            // highlight meets its neighbor's, and the last one ends one highlight inset above the card's
            // bottom edge — leaving the content the same `cardPadding` from every card edge.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(family.accounts) { account($0) }
            }
            .padding(.horizontal, density.cardPadding)
            .padding(.bottom, density.accountHighlightInset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

/// The provider's quick links in the card header: "Status ↗  Dashboard ↗" in small secondary text that
/// brightens under the pointer.
private struct ProviderHeaderLinks: View {
    let links: [ProviderLink]

    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular

    var body: some View {
        HStack(spacing: 10) {
            ForEach(links, id: \.self) { HeaderLink(link: $0, pointSize: density.supportingPointSize - 1) }
        }
    }
}

private struct HeaderLink: View {
    let link: ProviderLink
    let pointSize: CGFloat

    @State private var isHovered = false

    var body: some View {
        Button {
            if let url = URL(string: link.url) { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 2) {
                Text(link.label)
                Image(systemName: "arrow.up.right")
                    .imageScale(.small)
            }
            .font(.system(size: pointSize, weight: .medium))
            .foregroundStyle(isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(link.label), opens in browser")
    }
}

import AppKit
import SwiftUI

/// One provider's section on the dashboard, laid out like a System Settings group: a small section
/// header (mark and name) over one grouped box holding each account as a row, with inset hairlines
/// between rows. Hovering the section reveals the provider's quick links (Status, Dashboard) at the header's trailing
/// edge, as small text links that open in the browser.
struct DashboardProviderCard<Account: View>: View {
    let family: DashboardFamily
    /// Wraps the header, so the dashboard can attach the card's drag gesture to it.
    var handle: (AnyView) -> AnyView = { $0 }
    @ViewBuilder var account: (DashboardAccount) -> Account

    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular
    /// Party easter egg: pulse the provider mark.
    @Environment(\.popoverPartyMode) private var partyMode
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: density.headerToCardSpacing + 2) {
            handle(AnyView(header))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(family.accounts.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider().padding(.leading, density.groupedRowInset)
                    }
                    account(item)
                }
            }
            .clipShape(Theme.cardShape)
            .cardSurface()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    private var header: some View {
        HStack(spacing: 6) {
            ProviderIcon(source: family.provider.icon, inset: 0.04)
                .frame(width: density.headerIconSize - 3, height: density.headerIconSize - 3)
                .partyPulse(partyMode)
            Text(family.provider.displayName)
                .font(.system(size: density.supportingPointSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            ProviderHeaderLinks(links: family.provider.visibleLinks)
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
        }
        .padding(.horizontal, density.groupedRowInset)
        .contentShape(Rectangle())
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

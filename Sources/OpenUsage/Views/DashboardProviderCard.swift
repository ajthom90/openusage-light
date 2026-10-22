import AppKit
import SwiftUI

/// One provider's section on the dashboard, laid out like a grouped form: a section header (mark and
/// name) over one grouped box holding each account as a block, with hairlines between the blocks inset to
/// the text on both sides. The box is drawn like a menu: an account's highlight is inset from the box's
/// edges with a concentric corner, and the text sits inside that highlight. Hovering the section reveals
/// the provider's quick links (Status, Dashboard) at the header's trailing edge, as small text links that
/// open in the browser.
struct DashboardProviderCard<Account: View>: View {
    let family: DashboardFamily
    /// Wraps the header, so the dashboard can attach the card's drag gesture to it.
    var handle: (AnyView) -> AnyView = { $0 }
    @ViewBuilder var account: (DashboardAccount) -> Account

    /// Party easter egg: pulse the provider mark.
    @Environment(\.popoverPartyMode) private var partyMode
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.headerSpacing) {
            handle(AnyView(header))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(family.accounts.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider()
                            .padding(.horizontal, DashboardBox.textInset)
                            .padding(.vertical, DashboardBox.highlightInset)
                    }
                    account(item)
                }
            }
            .padding(.vertical, DashboardBox.highlightInset)
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
                .frame(width: 14, height: 14)
                .partyPulse(partyMode)
            Text(family.provider.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            ProviderHeaderLinks(links: family.provider.visibleLinks)
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
        }
        .padding(.horizontal, DashboardBox.textInset)
        .contentShape(Rectangle())
    }
}

/// Where things sit inside a provider's grouped box. An account's highlight is inset from the box's
/// edges, with the box's corner radius minus that inset so the two corners stay concentric, and the
/// text sits 10 pt inside the highlight.
enum DashboardBox {
    static let highlightInset: CGFloat = 4
    static let highlightCornerRadius: CGFloat = Theme.cardCornerRadius - highlightInset
    static let textInset: CGFloat = highlightInset + 10
}

/// The provider's quick links in the card header: "Status ↗  Dashboard ↗" in small secondary text that
/// brightens under the pointer.
private struct ProviderHeaderLinks: View {
    let links: [ProviderLink]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(links, id: \.self) { HeaderLink(link: $0) }
        }
    }
}

private struct HeaderLink: View {
    let link: ProviderLink

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
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(link.label), opens in browser")
    }
}

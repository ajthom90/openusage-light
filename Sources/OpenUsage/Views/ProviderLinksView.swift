import AppKit
import SwiftUI

/// The row of per-provider quick-link buttons (e.g. "Status", "Dashboard") shown under an account's
/// lines when the account is clicked. Up to three across; extra links wrap. Each button opens its URL
/// in the default browser. Flush with the metric lines above it.
struct ProviderLinksView: View {
    let links: [ProviderLink]
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular

    /// Hard ceiling from #596: never more than three buttons across, regardless of how many links a
    /// provider ships. Fewer links use fewer columns so a lone button isn't boxed into a third of the row.
    private static let maxColumns = 3

    private var columns: [GridItem] {
        let count = min(Self.maxColumns, max(1, links.count))
        return Array(repeating: GridItem(.flexible(), spacing: density.expandedGridSpacing, alignment: .top),
                     count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: density.expandedGridSpacing) {
            ForEach(links, id: \.self) { link in
                linkButton(link)
            }
        }
        .padding(.top, density.textRowPadding + 2)
        .padding(.bottom, density.textRowPadding)
    }

    private func linkButton(_ link: ProviderLink) -> some View {
        Button {
            if let url = URL(string: link.url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 4) {
                Text(link.label)
                    .font(.system(size: density.supportingPointSize, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: density.supportingPointSize - 2))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .glassButtonStyle()
        .controlSize(.small)
        .accessibilityLabel("\(link.label), opens in browser")
    }
}

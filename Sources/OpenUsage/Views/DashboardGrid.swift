import AppKit
import SwiftUI

/// Where things sit on the dashboard, on the 4/8/12/16 scale: a provider's header sits 4 pt above its
/// card and 16 pt below the card before it; the card pads its rows by 8 and each row, caption and the
/// header inset their text by 4 more, so every line starts 12 pt in from the card's edge and the logo
/// ends 12 pt before it, in line with the bars. Rows are 20 pt, captions 16, bars 6. The label column is
/// one width for the whole panel: the widest label, at least 96 pt.
enum DashboardGrid {
    /// Inside the card, around its rows.
    static let cardPadding = Theme.Spacing.m
    /// Inside a row, caption or header, around its text; with `cardPadding` the text starts 12 pt in.
    static let inset = Theme.Spacing.xs
    static let headerHeight: CGFloat = 20
    /// From a provider's header to its card.
    static let headerGap = Theme.Spacing.xs
    /// From a provider's card to the next provider's header.
    static let sectionSpacing = Theme.Spacing.xxxl
    /// Between two accounts in one card.
    static let accountSpacing = Theme.Spacing.xxxl
    static let captionHeight: CGFloat = 16
    static let rowHeight: CGFloat = 20
    /// From the label column to the bar, and from the plan to the logo.
    static let columnGap = Theme.Spacing.m
    static let minimumLabelWidth: CGFloat = 96
    static let barHeight: CGFloat = 6
    /// The provider's logo, and the copy button in its place.
    static let iconSize: CGFloat = 16
    /// The hovered row's highlight.
    static let highlightRadius: CGFloat = 6

    /// The label column for a panel showing `labels`: the widest, at least `minimumLabelWidth`.
    static func labelWidth(for labels: [String]) -> CGFloat {
        let font = NSFont.preferredFont(forTextStyle: .body)
        let widest = labels.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return max(minimumLabelWidth, widest.rounded(.up))
    }

    static func labelWidth(for families: [DashboardFamily]) -> CGFloat {
        labelWidth(for: families.flatMap { $0.accounts.flatMap { $0.lines.map(\.data.title) } })
    }
}

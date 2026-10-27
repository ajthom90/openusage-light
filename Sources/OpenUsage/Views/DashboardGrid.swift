import AppKit
import SwiftUI

/// Where things sit on the dashboard, on the 4/8/12/16 scale: a provider's header sits 4 pt above its
/// card and 16 pt below the card before it; the card pads its rows by 8 and each row, caption and the
/// header inset their text by 4 more, so every line starts 12 pt in from the card's edge and the logo
/// ends 12 pt before it, where the reset column ends. Rows are 20 pt, bars 5. The header and the
/// caption are as tall as one line of their type, and the logo is as tall as the header. A row's
/// columns are fixed — 86 pt of label, the bar, 52 of value, 56 of reset, 8 between — so every bar in
/// the panel starts and ends at the same x.
enum DashboardGrid {
    /// The card on the dashboard: the panel minus its margin on each side.
    static let cardWidth = PanelMetrics.width - 2 * PanelMetrics.margin
    /// Inside the card, around its rows.
    static let cardPadding = Theme.Spacing.m
    /// Inside a row, caption or header, around its text; with `cardPadding` the text starts 12 pt in.
    static let inset = Theme.Spacing.xs
    /// From a provider's header to its card.
    static let headerGap = Theme.Spacing.xs
    /// From a provider's card to the next provider's header.
    static let sectionSpacing = Theme.Spacing.xxxl
    /// Between two accounts in one card.
    static let accountSpacing = Theme.Spacing.xxxl
    static let rowHeight: CGFloat = 20
    /// Between a row's columns, and from the plan to the logo.
    static let columnGap = Theme.Spacing.m
    static let labelWidth: CGFloat = 86
    static let valueWidth: CGFloat = 52
    static let resetWidth: CGFloat = 56
    static let barHeight: CGFloat = 5

    // MARK: - Type

    /// The provider's header: Headline, the system's section title, over Callout rows.
    static let headerFont: Font = .headline
    /// The header's type as AppKit measures it.
    static var headerNSFont: NSFont { .preferredFont(forTextStyle: .headline) }
    /// A plan, in the header or on a caption: Subheadline.
    static let planFont: Font = .subheadline
    static var planNSFont: NSFont { .preferredFont(forTextStyle: .subheadline) }
    /// An account's caption in a card of several accounts: Subheadline Semibold.
    static let captionFont: Font = .subheadline.weight(.semibold)

    /// The header is one line of its type.
    static let headerHeight = lineHeight(headerNSFont)
    /// A caption is one line of its type.
    static let captionHeight = lineHeight(planNSFont)
    /// The provider's logo, and the copy button in its place: as tall as the header's line.
    static let iconSize = headerHeight

    /// The height of one line of `font`, in whole points.
    static func lineHeight(_ font: NSFont) -> CGFloat {
        NSLayoutManager().defaultLineHeight(for: font).rounded(.up)
    }
}

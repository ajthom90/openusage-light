import SwiftUI

/// The image the copy button and the right-click "Share Screenshot" put on the clipboard: one provider's
/// header and card as the dashboard draws them at rest — no hover, no popover, the logo in place — on the
/// panel's background, with the watermark footer, rasterized at ×4. An account named by its email reads
/// as its provider alone, so the email never leaves the panel. The view takes already-resolved data, so
/// it has no environment dependency and renders the same way in the app and in tests.
struct ShareCardView: View {
    let family: DashboardFamily
    /// The plan of an account, by its id.
    var plans: [String: String] = [:]
    let appearance: ColorScheme

    /// Authored card width in points. The renderer multiplies this by `ShareCardRenderer.scale` for the
    /// PNG's pixel width; the height is whatever the rows add up to (flexible).
    static let width: CGFloat = 360
    /// The chrome's padding around the card, on every side.
    static let inset: CGFloat = 16
    /// What the card has to draw in.
    static let contentWidth = width - 2 * inset

    var body: some View {
        let shown = family.hidingEmails
        ShareCardChrome(appearance: appearance) {
            DashboardProviderSection(family: shown, plans: plans, width: Self.contentWidth) {
                ProviderIcon(source: shown.provider.icon, inset: 0.04)
            } account: { account, captioned in
                DashboardAccountRows(account: account, plan: plans[account.id], captioned: captioned)
            }
        }
    }
}

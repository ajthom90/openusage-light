import CoreGraphics

/// The popover's one set of spaces, shared by every screen. There are no density levels: text uses the
/// system text styles (on macOS, body is 13 pt and subheadline 11 pt), and these are the gaps around it,
/// taken from `Theme.Spacing`. The dashboard's cards have their own, tighter steps (`DashboardBox`).
enum PanelMetrics {
    /// The panel's width on every screen.
    static let width: CGFloat = 340
    /// Inset from the panel's edge to its content, on every side of every screen.
    static let margin = Theme.Spacing.xxl
    /// Gap between two grouped boxes in Settings and on an account's page.
    static let sectionSpacing = Theme.Spacing.xxl
    /// Gap between a section's header and its grouped box.
    static let headerSpacing = Theme.Spacing.s
    /// Vertical padding of a Settings or Accounts row that holds a control.
    static let controlRowPadding: CGFloat = 9
}

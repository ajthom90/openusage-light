import CoreGraphics

/// The popover's one set of spaces, shared by every screen. There are no density levels: text uses the
/// system text styles (on macOS, body is 13 pt and subheadline 11 pt), and these are the gaps around it.
enum PanelMetrics {
    /// The panel's width on every screen.
    static let width: CGFloat = 340
    /// Inset from the panel's edge to its content, on every side of every screen.
    static let margin: CGFloat = 14
    /// Gap between two grouped boxes: two providers on the dashboard, two sections in Settings.
    static let sectionSpacing: CGFloat = 14
    /// Gap between a section's header and its grouped box.
    static let headerSpacing: CGFloat = 6
    /// Vertical padding of a Settings or Accounts row that holds a control.
    static let controlRowPadding: CGFloat = 9
}

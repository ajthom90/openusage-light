import Foundation

/// A provider metric's identity and presentation template. Live provider lines supply the values;
/// `sample` carries stable display metadata such as title, icon, kind, and descriptor opt-ins.
struct WidgetDescriptor: Identifiable, Hashable {
    let id: String                 // "claude.session"
    let providerID: String
    let metricLabel: String
    let sample: WidgetData
    /// Whether this widget can be pinned to the menu-bar strip.
    var pinnable: Bool = true

    /// The metric's single display name.
    var title: String { sample.title }

    static func == (lhs: WidgetDescriptor, rhs: WidgetDescriptor) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

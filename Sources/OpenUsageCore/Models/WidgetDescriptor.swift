import Foundation

/// A provider metric's identity and presentation template. Live provider lines supply the values;
/// `sample` carries stable display metadata such as title, icon, kind, and descriptor opt-ins.
package struct WidgetDescriptor: Identifiable, Hashable {
    package let id: String                 // "claude.session"
    package let providerID: String
    package let metricLabel: String
    package let sample: WidgetData
    /// Whether this widget can be pinned to the menu-bar strip.
    package var pinnable: Bool = true

    /// The metric's single display name.
    package var title: String { sample.title }

    package static func == (lhs: WidgetDescriptor, rhs: WidgetDescriptor) -> Bool { lhs.id == rhs.id }
    package func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

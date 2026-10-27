import Foundation

/// One widget placed on the dashboard. Stable `id` so reordering/animation is identity-based;
/// `descriptorID` links back to the registry for its data + render kind.
package struct PlacedWidget: Identifiable, Hashable, Codable {
    package var id: UUID
    package let descriptorID: String

    package init(id: UUID = UUID(), descriptorID: String) {
        self.id = id
        self.descriptorID = descriptorID
    }
}

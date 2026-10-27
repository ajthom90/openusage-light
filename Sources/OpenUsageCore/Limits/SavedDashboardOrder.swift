import Foundation

/// The user's saved dashboard order, read from the same settings the dashboard writes. The key
/// format mirrors the Mac app's `LayoutPersistence`; a test there keeps the two in agreement.
package enum SavedDashboardOrder {
    package static let defaultStorageKey = "openusage.layout.v1"

    /// Account card ids in the order the user arranged them, or empty when they never reordered.
    package static func providerOrder(in settings: any SettingsStore, storageKey: String = defaultStorageKey) -> [String] {
        guard let data = settings.data(forKey: "\(storageKey).providerOrder"),
              let order = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return order
    }
}

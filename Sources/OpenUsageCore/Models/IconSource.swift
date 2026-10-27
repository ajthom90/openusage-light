import Foundation

/// A provider's copied vector mark, keyed by provider id.
package struct IconSource: Hashable {
    package let providerID: String

    /// Named constructor retained at call sites so the stored string's meaning stays explicit.
    package static func providerMark(_ providerID: String) -> IconSource {
        IconSource(providerID: providerID)
    }
}

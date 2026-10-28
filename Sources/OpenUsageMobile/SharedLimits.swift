import Foundation

/// The last limits document the app received, kept where the widget can read it too (an App Group), so a
/// widget that cannot reach iCloud still shows the last known numbers.
public enum SharedLimits {
    private static let key = "openusage.limits.saved"

    /// The App Group this build was signed with, or `nil` when it has none (the standard defaults are used).
    public static var groupIdentifier: String? {
        (Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    public static var defaults: UserDefaults {
        groupIdentifier.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    public static func save(_ document: Data, to defaults: UserDefaults = SharedLimits.defaults) {
        defaults.set(document, forKey: key)
    }

    public static func load(from defaults: UserDefaults = SharedLimits.defaults) -> Data? {
        defaults.data(forKey: key)
    }
}

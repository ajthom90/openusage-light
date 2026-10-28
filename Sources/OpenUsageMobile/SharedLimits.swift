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

/// Whether a meter reads as what has been used or what is left.
public enum UsageDisplay: String, Sendable, CaseIterable {
    case used, remaining
}

/// The user's choice on the phone: follow the Mac, or always show one reading.
public enum DisplayChoice: String, Sendable, CaseIterable, Identifiable {
    case followMac, remaining, used

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .followMac: "Same as Mac"
        case .remaining: "Left"
        case .used: "Used"
        }
    }
}

extension SharedLimits {
    private static let macDisplayKey = "openusage.display.mac"
    private static let choiceKey = "openusage.display.choice"

    /// How the Mac's user reads usage, as last published. The Mac's own default is "left".
    public static func saveMacDisplay(_ mode: String?, to defaults: UserDefaults = SharedLimits.defaults) {
        if let mode { defaults.set(mode, forKey: macDisplayKey) }
    }

    public static func loadChoice(from defaults: UserDefaults = SharedLimits.defaults) -> DisplayChoice {
        defaults.string(forKey: choiceKey).flatMap(DisplayChoice.init(rawValue:)) ?? .followMac
    }

    public static func saveChoice(_ choice: DisplayChoice, to defaults: UserDefaults = SharedLimits.defaults) {
        defaults.set(choice.rawValue, forKey: choiceKey)
    }

    /// The reading to draw: the user's own choice, else the Mac's, else "left".
    public static func resolvedDisplay(from defaults: UserDefaults = SharedLimits.defaults) -> UsageDisplay {
        switch loadChoice(from: defaults) {
        case .remaining: return .remaining
        case .used: return .used
        case .followMac: return defaults.string(forKey: macDisplayKey).flatMap(UsageDisplay.init(rawValue:)) ?? .remaining
        }
    }
}

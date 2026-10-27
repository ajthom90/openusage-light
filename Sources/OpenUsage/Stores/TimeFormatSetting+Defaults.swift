import Foundation
import OpenUsageCore

extension TimeFormatSetting {
    /// Reads the saved choice into `current`, which the core's formatters use. Called at launch and
    /// whenever the Settings picker changes.
    static func loadCurrent(from defaults: UserDefaults = .standard) {
        current = defaults.enumValue(forKey: key, default: fallback)
    }
}

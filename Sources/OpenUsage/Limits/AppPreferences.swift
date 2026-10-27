import Foundation
import OpenUsageCore

/// Finds the preferences of the OpenUsage Light app the `openusage` command belongs to.
///
/// The command is a helper inside the app bundle, so its own preferences domain is not the app's. The
/// app's saved accounts, order and cached snapshots live under the app's bundle identifier, which is
/// read from the enclosing bundle's Info.plist, so a dev build reads the dev app and a release build
/// the release app.
enum AppPreferences {
    /// The Info.plist identifier of the `.app` that contains `executable`, or `nil` outside a bundle.
    static func bundleIdentifier(containing executable: URL) -> String? {
        var url = executable.resolvingSymlinksInPath()
        while url.path != "/" {
            url.deleteLastPathComponent()
            guard url.pathExtension == "app" else { continue }
            return Bundle(url: url)?.bundleIdentifier
        }
        return nil
    }

    /// Inside the app bundle the process's own domain already is the app's (`Bundle.main` resolves to the
    /// enclosing app), and a process may not open its own identifier as a suite, so that case is
    /// `.standard`. A command run from anywhere else opens the app's domain by identifier.
    static func defaults(
        executable: URL? = Bundle.main.executableURL,
        ownIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> UserDefaults {
        guard let executable,
              let identifier = bundleIdentifier(containing: executable),
              identifier != ownIdentifier,
              let suite = UserDefaults(suiteName: identifier) else { return .standard }
        return suite
    }
}

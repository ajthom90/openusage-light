import Foundation

/// The public OAuth client identifiers the providers' token refreshes use. The sign-in flows (which
/// live with each platform's UI) and the refresh code in the runtimes share these values.
package enum OAuthClients {
    package static let claudeClientID = String(data: Data(base64Encoded: "OWQxYzI1MGEtZTYxYi00NGQ5LTg4ZWQtNTk0NGQxOTYyZjVl")!, encoding: .utf8)!
    /// Muse Code's public sign-in client (the same identifier its own launcher uses).
    package static let museCodeClientID = "1031625952748946"
    package static let grokClientID = "b1a00492-073a-47ea-816f-4c329264a828"
    package static let antigravityClientID = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
    package static let antigravityClientSecret = "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"
}

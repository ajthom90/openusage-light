
package enum ProviderUsageErrorText {
    package static let connectionFailed = "Connection failed. Check your internet connection and try again."
    package static let invalidResponse = "The provider returned an invalid response."

    package static func requestFailed(statusCode: Int) -> String {
        "The provider request failed (HTTP \(statusCode))."
    }
}

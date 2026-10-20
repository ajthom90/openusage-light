enum ProviderUsageErrorText {
    static let connectionFailed = "Connection failed. Check your internet connection and try again."
    static let invalidResponse = "The provider returned an invalid response."

    static func requestFailed(statusCode: Int) -> String {
        "The provider request failed (HTTP \(statusCode))."
    }
}

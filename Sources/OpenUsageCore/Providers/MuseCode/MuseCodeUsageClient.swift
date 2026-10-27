import Foundation

package enum MuseCodeAuthError: Error, LocalizedError, Equatable {
    case signInExpired

    package var errorDescription: String? {
        "Muse Code sign-in expired. Add the account again."
    }
}

package enum MuseCodeUsageError: Error, LocalizedError, Equatable {
    case connectionFailed
    case invalidResponse
    case requestFailed(Int)
    /// The sign-in works but the account has no active Muse Code subscription, so there is no allowance.
    case noSubscription

    package var errorDescription: String? {
        switch self {
        case .connectionFailed: ProviderUsageErrorText.connectionFailed
        case .invalidResponse: ProviderUsageErrorText.invalidResponse
        case .requestFailed(let status): ProviderUsageErrorText.requestFailed(statusCode: status)
        case .noSubscription: "No active Muse Code subscription. Subscribe in your Meta Accounts Center to see usage."
        }
    }
}

/// Muse Code's subscription allowance. Meta documents no usage endpoint; the data rides on the response
/// to the request Muse Code's own sign-in makes to turn its login into a working key. That request is a
/// `POST` with the sign-in token and returns the plan and `subs_usage` (5-hour window and weekly). The
/// same call returns the account's key, name, and email; nothing here reads or keeps those. The call
/// gives the same key every time for a sign-in, so polling does not create keys.
package struct MuseCodeUsageClient: Sendable {
    package static let url = URL(string: "https://api.meta.ai/muse-code/key")!

    package var http: any HTTPClient

    package init(http: any HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    package func fetchSubscription(token: String) async throws -> HTTPResponse {
        try await http.send(HTTPRequest(
            method: "POST",
            url: Self.url,
            headers: [
                "Authorization": "Bearer \(token)",
                "Accept": "application/json",
                "Content-Type": "application/x-www-form-urlencoded"
            ],
            body: Data(),
            timeout: 15
        ))
    }
}

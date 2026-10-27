import Foundation

/// Calls OpenCode's official Go usage endpoint with the local `opencode-go` API key.
package struct OpenCodeUsageClient: Sendable {
    package static let usageURL = URL(string: "https://opencode.ai/zen/go/v1/usage")!

    package var http: any HTTPClient

    package init(http: any HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    package func fetchUsage(apiKey: String) async throws -> HTTPResponse {
        try await http.send(HTTPRequest(
            method: "GET",
            url: Self.usageURL,
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Accept": "application/json"
            ],
            timeout: 15
        ))
    }
}

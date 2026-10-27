import Foundation

/// Calls GitHub's internal Copilot usage endpoint with a GitHub OAuth token. Mirrors the headers the
/// official Copilot client sends; `Authorization` uses the `token` scheme (not `Bearer`), which is what
/// `/copilot_internal/user` accepts.
package struct CopilotUsageClient: Sendable {
    package static let usageURL = "https://api.github.com/copilot_internal/user"

    package var http: any HTTPClient

    package init(http: any HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    package func fetchUsage(token: String) async throws -> HTTPResponse {
        guard let url = URL(string: Self.usageURL) else {
            throw CopilotUsageError.invalidResponse
        }

        return try await http.send(HTTPRequest(
            method: "GET",
            url: url,
            headers: [
                "Authorization": "token \(token)",
                "Accept": "application/json",
                "Editor-Version": "vscode/1.96.2",
                "Editor-Plugin-Version": "copilot-chat/0.26.7",
                "User-Agent": "GitHubCopilotChat/0.26.7",
                "X-Github-Api-Version": "2025-04-01"
            ],
            timeout: 15
        ))
    }
}

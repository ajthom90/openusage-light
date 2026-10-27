import Foundation

package struct OpenRouterUsageClient: Sendable {
    package static let creditsURL = "https://openrouter.ai/api/v1/credits"
    package static let keyURL = "https://openrouter.ai/api/v1/key"

    package var http: any HTTPClient

    package init(http: any HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    /// Account-wide credit balance and lifetime spend. Fetched independently from key metadata because
    /// OpenRouter can gate either endpoint for a particular key type.
    package func fetchCredits(apiKey: String) async throws -> HTTPResponse {
        try await get(Self.creditsURL, apiKey: apiKey)
    }

    /// Best-effort key metadata: tier and daily/weekly/monthly spend.
    package func fetchKey(apiKey: String) async throws -> HTTPResponse {
        try await get(Self.keyURL, apiKey: apiKey)
    }

    private func get(_ urlString: String, apiKey: String) async throws -> HTTPResponse {
        guard let url = URL(string: urlString) else {
            throw OpenRouterUsageError.invalidResponse
        }

        return try await http.send(HTTPRequest(
            method: "GET",
            url: url,
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Accept": "application/json"
            ],
            timeout: 15
        ))
    }
}

package enum OpenRouterUsageError: Error, LocalizedError, Equatable {
    case connectionFailed
    case invalidResponse
    case requestFailed(Int)

    package var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Couldn't reach OpenRouter. Check your connection."
        case .invalidResponse:
            return "OpenRouter usage data unavailable. Try again later."
        case .requestFailed(let status):
            return "OpenRouter request failed (HTTP \(status))."
        }
    }
}

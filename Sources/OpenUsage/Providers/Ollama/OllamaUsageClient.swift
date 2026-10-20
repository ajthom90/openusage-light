import Foundation

/// Calls Ollama's account endpoints using the key the user entered in the app.
///
/// - `GET /api/balance` — the plan's included allowance (monthly credits, or session and weekly limits
///   on legacy plans) plus purchased credits. Documented at https://docs.ollama.com/api/balance; the
///   local Ollama server proxies the same endpoint to ollama.com signed with this same key.
/// - `POST /api/me` — the account's plan name (`free` / `pro` / `max`), used only for the plan badge.
struct OllamaUsageClient: Sendable {
    static let host = "https://ollama.com"
    static let balancePath = "/api/balance"
    static let accountPath = "/api/me"

    var http: any HTTPClient

    init(http: any HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    /// Included and purchased credits. Required for a usable snapshot.
    func fetchBalance(apiKey: String) async throws -> HTTPResponse {
        try await send(method: "GET", path: Self.balancePath, apiKey: apiKey)
    }

    /// The signed-in account — best-effort, used only to surface the plan name.
    func fetchAccount(apiKey: String) async throws -> HTTPResponse {
        try await send(method: "POST", path: Self.accountPath, apiKey: apiKey)
    }

    private func send(method: String, path: String, apiKey: String) async throws -> HTTPResponse {
        guard let url = URL(string: Self.host + path) else {
            throw OllamaUsageError.invalidResponse
        }
        return try await http.send(HTTPRequest(
            method: method,
            url: url,
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Accept": "application/json"
            ],
            timeout: 15
        ))
    }
}

enum OllamaUsageError: Error, LocalizedError, Equatable {
    case connectionFailed
    case invalidResponse
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return ProviderUsageErrorText.connectionFailed
        case .invalidResponse:
            return ProviderUsageErrorText.invalidResponse
        case .requestFailed(let status):
            return ProviderUsageErrorText.requestFailed(statusCode: status)
        }
    }
}

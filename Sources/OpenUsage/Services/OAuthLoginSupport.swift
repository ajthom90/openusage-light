import Foundation

struct LoginHTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
}

enum LoginHTTP {
    static func send(_ request: HTTPRequest, using client: any HTTPClient) async throws -> LoginHTTPResponse {
        let response = try await client.send(request)
        return LoginHTTPResponse(data: response.body, statusCode: response.statusCode)
    }

    static func postForm(
        _ url: URL,
        fields: [String: String],
        using client: any HTTPClient,
        headers: [String: String] = [:]
    ) async throws -> LoginHTTPResponse {
        var requestHeaders = [
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json"
        ]
        requestHeaders.merge(headers) { _, new in new }
        let body = fields
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? "")" }
            .sorted()
            .joined(separator: "&")
            .data(using: .utf8)
        return try await send(HTTPRequest(method: "POST", url: url, headers: requestHeaders, body: body), using: client)
    }

    static func postJSON(
        _ url: URL,
        fields: [String: String],
        using client: any HTTPClient
    ) async throws -> LoginHTTPResponse {
        let request = HTTPRequest(
            method: "POST",
            url: url,
            headers: ["Content-Type": "application/json"],
            body: try JSONSerialization.data(withJSONObject: fields)
        )
        return try await send(request, using: client)
    }

    static func get(
        _ url: URL,
        bearerToken: String? = nil,
        using client: any HTTPClient,
        headers: [String: String] = [:]
    ) async throws -> LoginHTTPResponse {
        var requestHeaders = headers
        if let bearerToken { requestHeaders["Authorization"] = "Bearer \(bearerToken)" }
        return try await send(HTTPRequest(method: "GET", url: url, headers: requestHeaders), using: client)
    }

    static func decode<T: Decodable>(_ type: T.Type, from response: LoginHTTPResponse) throws -> T {
        guard (200..<300).contains(response.statusCode) else {
            throw LoginError.requestFailed(response.statusCode)
        }
        return try JSONDecoder().decode(type, from: response.data)
    }

    static func requireSuccess(_ response: LoginHTTPResponse) throws {
        guard (200..<300).contains(response.statusCode) else {
            throw LoginError.requestFailed(response.statusCode)
        }
    }

    static func jsonObject(_ response: LoginHTTPResponse) -> [String: String] {
        guard let values = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any] else { return [:] }
        return values.compactMapValues { $0 as? String }
    }

    static func jwtPayload(_ token: String) -> Data? {
        let parts = token.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        return Data(base64Encoded: payload)
    }
}

enum LoginError: LocalizedError, Sendable {
    case cancelled
    case invalidResponse
    case requestFailed(Int)
    case missingField(String)
    case invalidState
    case invalidCode

    var errorDescription: String? {
        switch self {
        case .cancelled: "Sign-in was cancelled."
        case .invalidResponse: "The sign-in service returned an invalid response."
        case .requestFailed(let status): "Sign-in failed with HTTP \(status)."
        case .missingField(let field): "The sign-in response did not include \(field)."
        case .invalidState: "The sign-in response did not match this request."
        case .invalidCode: "The authorization code was invalid."
        }
    }
}

enum AuthorizationInput: Sendable {
    case callback(String)
    case pasted(String)
}

func waitForAuthorizationInput(
    server: LoopbackCallbackServer,
    pastedCode: AsyncStream<String>
) async throws -> AuthorizationInput {
    try await withTaskCancellationHandler {
        try await withThrowingTaskGroup(of: AuthorizationInput.self) { tasks in
            tasks.addTask { .callback(try await server.waitForCode()) }
            tasks.addTask {
                var iterator = pastedCode.makeAsyncIterator()
                guard let value = await iterator.next() else { throw LoginError.cancelled }
                return .pasted(value)
            }
            guard let result = try await tasks.next() else { throw LoginError.cancelled }
            server.cancel()
            tasks.cancelAll()
            return result
        }
    } onCancel: {
        server.cancel()
    }
}

func authorizationCode(
    from input: AuthorizationInput,
    expectedState: String,
    requireState: Bool
) throws -> String {
    switch input {
    case .callback(let code):
        return code
    case .pasted(let value):
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed: (code: String?, state: String?)
        if let url = URL(string: trimmed), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            parsed = (
                components.queryItems?.first(where: { $0.name == "code" })?.value,
                components.queryItems?.first(where: { $0.name == "state" })?.value
            )
        } else if trimmed.contains("#") {
            let values = trimmed.split(separator: "#", maxSplits: 1).map(String.init)
            parsed = (values.first, values.count > 1 ? values[1] : nil)
        } else {
            parsed = (trimmed, nil)
        }
        guard let code = parsed.code, !code.isEmpty else { throw LoginError.invalidCode }
        if (requireState && parsed.state == nil) || (parsed.state != nil && parsed.state != expectedState) {
            throw LoginError.invalidState
        }
        return code
    }
}

private extension CharacterSet {
    static let urlQueryValueAllowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
}

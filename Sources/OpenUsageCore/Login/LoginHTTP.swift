import Foundation

package struct LoginHTTPResponse: Sendable {
    package let data: Data
    package let statusCode: Int
}

package enum LoginHTTP {
    package static func send(_ request: HTTPRequest, using client: any HTTPClient) async throws -> LoginHTTPResponse {
        let response = try await client.send(request)
        return LoginHTTPResponse(data: response.body, statusCode: response.statusCode)
    }

    package static func postForm(
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

    package static func postJSON(
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

    package static func get(
        _ url: URL,
        bearerToken: String? = nil,
        using client: any HTTPClient,
        headers: [String: String] = [:]
    ) async throws -> LoginHTTPResponse {
        var requestHeaders = headers
        if let bearerToken { requestHeaders["Authorization"] = "Bearer \(bearerToken)" }
        return try await send(HTTPRequest(method: "GET", url: url, headers: requestHeaders), using: client)
    }

    package static func decode<T: Decodable>(_ type: T.Type, from response: LoginHTTPResponse) throws -> T {
        guard (200..<300).contains(response.statusCode) else {
            throw LoginError.requestFailed(response.statusCode)
        }
        return try JSONDecoder().decode(type, from: response.data)
    }

    package static func requireSuccess(_ response: LoginHTTPResponse) throws {
        guard (200..<300).contains(response.statusCode) else {
            throw LoginError.requestFailed(response.statusCode)
        }
    }

    package static func jsonObject(_ response: LoginHTTPResponse) -> [String: String] {
        guard let values = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any] else { return [:] }
        return values.compactMapValues { $0 as? String }
    }

    package static func jwtPayload(_ token: String) -> Data? {
        let parts = token.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        return Data(base64Encoded: payload)
    }
}

private extension CharacterSet {
    package static let urlQueryValueAllowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
}

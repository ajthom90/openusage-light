import Foundation

package struct CopilotLogin: ProviderLogin {
    package static let clientID = String(data: Data(base64Encoded: "SXYxLmI1MDdhMDhjODdlY2ZlOTg=")!, encoding: .utf8)!
    package var http: any HTTPClient = URLSessionHTTPClient()

    package func login(prompt: @Sendable (LoginPrompt) async -> Void, pastedCode: AsyncStream<String>) async throws -> (label: String, credential: AccountCredential) {
        let startURL = URL(string: "https://github.com/login/device/code")!
        let startResponse = try await LoginHTTP.postForm(startURL, fields: [
            "client_id": Self.clientID,
            "scope": "read:user"
        ], using: http, headers: ["User-Agent": "OpenUsage Light"])
        let device = try LoginHTTP.decode(GitHubDeviceCode.self, from: startResponse)
        guard let verificationURL = URL(string: device.verificationURI), verificationURL.scheme == "https" else {
            throw LoginError.invalidResponse
        }
        await prompt(.deviceCode(userCode: device.userCode, verificationURL: verificationURL))
        let token: GitHubDeviceToken = try await DeviceCodePoller.poll(
            interval: device.interval ?? 5,
            expiresIn: TimeInterval(device.expiresIn)
        ) { [http] in
            let response = try await LoginHTTP.postForm(URL(string: "https://github.com/login/oauth/access_token")!, fields: [
                "client_id": Self.clientID,
                "device_code": device.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ], using: http, headers: ["User-Agent": "OpenUsage Light"])
            let values = LoginHTTP.jsonObject(response)
            if let accessToken = values["access_token"] {
                return .complete(GitHubDeviceToken(accessToken: accessToken))
            }
            return switch values["error"] {
            case "authorization_pending": DeviceCodePollResult<GitHubDeviceToken>.pending
            case "slow_down": DeviceCodePollResult<GitHubDeviceToken>.slowDown
            case "expired_token": DeviceCodePollResult<GitHubDeviceToken>.failed("GitHub device sign-in expired.")
            case "access_denied": DeviceCodePollResult<GitHubDeviceToken>.failed("GitHub device sign-in was denied.")
            default: DeviceCodePollResult<GitHubDeviceToken>.failed("GitHub device sign-in failed.")
            }
        }
        let profileURL = URL(string: "https://api.github.com/user")!
        let profile = try await LoginHTTP.get(profileURL, bearerToken: token.accessToken, using: http, headers: [
            "Accept": "application/vnd.github+json",
            "User-Agent": "OpenUsage Light",
            "X-GitHub-Api-Version": "2022-11-28"
        ])
        let user = try LoginHTTP.decode(GitHubUser.self, from: profile)
        return (user.login, .oauth(OAuthTokens(accessToken: token.accessToken)))
    }
}

package struct GrokLogin: ProviderLogin {
    package static let clientID = OAuthClients.grokClientID
    package static let scopes = "openid profile email offline_access grok-cli:access api:access"
    package var http: any HTTPClient = URLSessionHTTPClient()

    package func login(prompt: @Sendable (LoginPrompt) async -> Void, pastedCode: AsyncStream<String>) async throws -> (label: String, credential: AccountCredential) {
        let start = try await LoginHTTP.postForm(URL(string: "https://auth.x.ai/oauth2/device/code")!, fields: [
            "client_id": Self.clientID,
            "scope": Self.scopes
        ], using: http)
        let device = try LoginHTTP.decode(XAIDeviceCode.self, from: start)
        guard let verificationURL = URL(string: device.verificationURI), verificationURL.scheme == "https" else {
            throw LoginError.invalidResponse
        }
        await prompt(.deviceCode(userCode: device.userCode, verificationURL: verificationURL))
        let token: OAuthTokenResponse = try await DeviceCodePoller.poll(
            interval: device.interval ?? 5,
            expiresIn: TimeInterval(device.expiresIn)
        ) { [http] in
            let response = try await LoginHTTP.postForm(URL(string: "https://auth.x.ai/oauth2/token")!, fields: [
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "client_id": Self.clientID,
                "device_code": device.deviceCode
            ], using: http)
            if (200..<300).contains(response.statusCode) {
                return .complete(try LoginHTTP.decode(OAuthTokenResponse.self, from: response))
            }
            let error = LoginHTTP.jsonObject(response)["error"] ?? ""
            if error == "authorization_pending" { return DeviceCodePollResult<OAuthTokenResponse>.pending }
            if error == "slow_down" { return DeviceCodePollResult<OAuthTokenResponse>.slowDown }
            if error == "expired_token" { return DeviceCodePollResult<OAuthTokenResponse>.failed("xAI device sign-in expired.") }
            return DeviceCodePollResult<OAuthTokenResponse>.failed("xAI device sign-in failed.")
        }
        let claims = token.accessToken.jwtPayload(as: GrokIDClaims.self)
        return (claims?.email ?? "Grok Account", .oauth(OAuthTokens(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: token.expiry
        )))
    }
}

package struct CursorLogin: ProviderLogin {
    package var http: any HTTPClient = URLSessionHTTPClient()

    package func login(prompt: @Sendable (LoginPrompt) async -> Void, pastedCode: AsyncStream<String>) async throws -> (label: String, credential: AccountCredential) {
        let pkce = PKCE.generate()
        let uuid = UUID().uuidString
        var components = URLComponents(string: "https://cursor.com/loginDeepControl")!
        components.queryItems = [
            URLQueryItem(name: "challenge", value: pkce.challenge),
            URLQueryItem(name: "uuid", value: uuid),
            URLQueryItem(name: "mode", value: "login"),
            URLQueryItem(name: "redirectTarget", value: "cli")
        ]
        guard let authorizeURL = components.url else { throw LoginError.invalidResponse }
        await prompt(.browser(authorizeURL, acceptsPastedCode: false))
        let token: CursorTokenResponse = try await DeviceCodePoller.poll(interval: 2, expiresIn: 300) { [http] in
            var poll = URLComponents(string: "https://api2.cursor.sh/auth/poll")!
            poll.queryItems = [
                URLQueryItem(name: "uuid", value: uuid),
                URLQueryItem(name: "verifier", value: pkce.verifier)
            ]
            guard let url = poll.url else { return .failed("Cursor sign-in URL was invalid.") }
            let response = try await LoginHTTP.get(url, using: http)
            if (200..<300).contains(response.statusCode),
               let token = try? LoginHTTP.decode(CursorTokenResponse.self, from: response),
               !token.accessToken.isEmpty, !token.refreshToken.isEmpty {
                return .complete(token)
            }
            if response.statusCode == 404 || response.statusCode == 202 { return .pending }
            return .failed("Cursor sign-in failed.")
        }
        return (token.userID ?? "Cursor Account", .oauth(OAuthTokens(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: ProviderParse.jwtExpiry(token.accessToken),
            extras: token.userID.map { ["userID": $0] } ?? [:]
        )))
    }
}

package struct APIKeyLogin: ProviderLogin {
    package let kind: ProviderKind

    package func login(prompt: @Sendable (LoginPrompt) async -> Void, pastedCode: AsyncStream<String>) async throws -> (label: String, credential: AccountCredential) {
        var iterator = pastedCode.makeAsyncIterator()
        guard let value = await iterator.next() else { throw LoginError.cancelled }
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw LoginError.invalidCode }
        return (kind.displayName, .apiKey(key))
    }
}

/// Every sign-in, built from code shared by all platforms. The browser sign-ins that wait for a redirect
/// need a local listener, which each platform supplies; without one they are not offered (`nil`).
package enum SharedProviderLogins {
    package static func login(for kind: ProviderKind, callbackServer: OAuthCallbackServerFactory?) -> (any ProviderLogin)? {
        switch kind {
        case .cursor: CursorLogin()
        case .copilot: CopilotLogin()
        case .grok: GrokLogin()
        case .musecode: MuseCodeLogin()
        case .ollama, .opencodeGo, .openrouter, .zai: APIKeyLogin(kind: kind)
        case .claude: callbackServer.map { ClaudeLogin(makeServer: $0) }
        case .codex: callbackServer.map { CodexLogin(makeServer: $0) }
        case .antigravity: callbackServer.map { AntigravityLogin(makeServer: $0) }
        }
    }
}

private struct GitHubDeviceCode: Decodable {
    package let deviceCode: String
    package let userCode: String
    package let verificationURI: String
    package let expiresIn: Int
    package let interval: TimeInterval?
    package enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct GitHubDeviceToken: Sendable {
    package let accessToken: String
}

private struct GitHubUser: Decodable {
    package let login: String
}

private struct XAIDeviceCode: Decodable {
    package let deviceCode: String
    package let userCode: String
    package let verificationURI: String
    package let expiresIn: Int
    package let interval: TimeInterval?
    package enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct OAuthTokenResponse: Decodable {
    package let accessToken: String
    package let refreshToken: String?
    package let expiresIn: Double?
    package let idToken: String?
    package enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case idToken = "id_token"
    }
    package var expiry: Date? { expiresIn.map { Date().addingTimeInterval(max(0, $0 - 300)) } }
}

private struct CursorTokenResponse: Decodable, Sendable {
    package let accessToken: String
    package let refreshToken: String
    package let userID: String?
}

private struct GrokIDClaims: Decodable {
    package let email: String?
}

import Foundation

package struct ClaudeLogin: ProviderLogin {
    package static let clientID = OAuthClients.claudeClientID
    package static let authorizeURL = URL(string: "https://claude.ai/oauth/authorize")!
    package static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    package static let scopes = "org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"
    package var http: any HTTPClient = URLSessionHTTPClient()
    package var makeServer: OAuthCallbackServerFactory

    package init(http: any HTTPClient = URLSessionHTTPClient(), makeServer: @escaping OAuthCallbackServerFactory) {
        self.http = http
        self.makeServer = makeServer
    }

    package func login(prompt: @Sendable (LoginPrompt) async -> Void, pastedCode: AsyncStream<String>) async throws -> (label: String, credential: AccountCredential) {
        let pkce = PKCE.generate()
        let server = try await makeServer(pkce.verifier, nil, "/callback")
        var components = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: server.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.verifier)
        ]
        guard let authorizeURL = components.url else { throw LoginError.invalidResponse }
        await prompt(.browser(authorizeURL, acceptsPastedCode: true))
        do {
            let input = try await waitForAuthorizationInput(server: server, pastedCode: pastedCode)
            let code = try authorizationCode(from: input, expectedState: pkce.verifier, requireState: true)
            let response = try await LoginHTTP.postJSON(Self.tokenURL, fields: [
                "grant_type": "authorization_code",
                "client_id": Self.clientID,
                "code": code,
                "state": pkce.verifier,
                "redirect_uri": server.redirectURI,
                "code_verifier": pkce.verifier
            ], using: http)
            let token = try LoginHTTP.decode(OAuthTokenResponse.self, from: response)
            var label = "Claude Account"
            if let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile"),
               let profile = try? await LoginHTTP.get(profileURL, bearerToken: token.accessToken, using: http),
               let info = try? LoginHTTP.decode(ClaudeProfileResponse.self, from: profile),
               let email = info.account?.email ?? info.email {
                label = email
            }
            return (label, .oauth(OAuthTokens(
                accessToken: token.accessToken,
                refreshToken: token.refreshToken,
                expiresAt: token.expiry
            )))
        } catch {
            server.cancel()
            throw error
        }
    }
}

package struct CodexLogin: ProviderLogin {
    package static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    package static let authorizeURL = URL(string: "https://auth.openai.com/oauth/authorize")!
    package static let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    package var http: any HTTPClient = URLSessionHTTPClient()
    package var makeServer: OAuthCallbackServerFactory

    package init(http: any HTTPClient = URLSessionHTTPClient(), makeServer: @escaping OAuthCallbackServerFactory) {
        self.http = http
        self.makeServer = makeServer
    }

    package func login(prompt: @Sendable (LoginPrompt) async -> Void, pastedCode: AsyncStream<String>) async throws -> (label: String, credential: AccountCredential) {
        let pkce = PKCE.generate()
        let state = UUID().uuidString
        let server: any OAuthCallbackServer
        do {
            server = try await makeServer(state, 1455, "/auth/callback")
        } catch let error as LoopbackCallbackError {
            guard case .listenerFailed = error else { throw error }
            return try await deviceLogin(prompt: prompt)
        } catch {
            return try await deviceLogin(prompt: prompt)
        }
        return try await browserLogin(server: server, pkce: pkce, state: state, prompt: prompt, pastedCode: pastedCode)
    }

    private func browserLogin(
        server: any OAuthCallbackServer,
        pkce: PKCEPair,
        state: String,
        prompt: @Sendable (LoginPrompt) async -> Void,
        pastedCode: AsyncStream<String>
    ) async throws -> (label: String, credential: AccountCredential) {
        var components = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: server.redirectURI),
            URLQueryItem(name: "scope", value: "openid profile email offline_access"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "originator", value: "pi")
        ]
            guard let url = components.url else { throw LoginError.invalidResponse }
        await prompt(.browser(url, acceptsPastedCode: true))
        do {
            let input = try await waitForAuthorizationInput(server: server, pastedCode: pastedCode)
            let code = try authorizationCode(from: input, expectedState: state, requireState: true)
            return try await exchange(code: code, verifier: pkce.verifier, redirectURI: server.redirectURI)
        } catch {
            server.cancel()
            throw error
        }
    }

    private func deviceLogin(prompt: @Sendable (LoginPrompt) async -> Void) async throws -> (label: String, credential: AccountCredential) {
        let deviceURL = URL(string: "https://auth.openai.com/api/accounts/deviceauth/usercode")!
        let start = try await LoginHTTP.postJSON(deviceURL, fields: ["client_id": Self.clientID], using: http)
        let device = try LoginHTTP.decode(CodexDeviceStart.self, from: start)
        let verifyURL = URL(string: "https://auth.openai.com/codex/device")!
        await prompt(.deviceCode(userCode: device.userCode, verificationURL: verifyURL))
        let deviceToken: CodexDeviceToken = try await DeviceCodePoller.poll(interval: device.interval, expiresIn: 900) { [http] in
            let url = URL(string: "https://auth.openai.com/api/accounts/deviceauth/token")!
            let response = try await LoginHTTP.postJSON(url, fields: [
                "device_auth_id": device.deviceAuthID,
                "user_code": device.userCode
            ], using: http)
            if (200..<300).contains(response.statusCode) {
                return .complete(try LoginHTTP.decode(CodexDeviceToken.self, from: response))
            }
            let error = LoginHTTP.jsonObject(response)["error"] ?? ""
            if response.statusCode == 403 || response.statusCode == 404 || error == "deviceauth_authorization_pending" {
                return .pending
            }
            if error == "slow_down" { return .slowDown }
            return .failed(error == "expired_token" ? "Device sign-in expired." : "Device sign-in failed.")
        }
        return try await exchange(
            code: deviceToken.authorizationCode,
            verifier: deviceToken.codeVerifier,
            redirectURI: "https://auth.openai.com/deviceauth/callback"
        )
    }

    private func exchange(code: String, verifier: String, redirectURI: String) async throws -> (label: String, credential: AccountCredential) {
        let response = try await LoginHTTP.postForm(Self.tokenURL, fields: [
            "grant_type": "authorization_code",
            "client_id": Self.clientID,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": redirectURI
        ], using: http)
        let token = try LoginHTTP.decode(OAuthTokenResponse.self, from: response)
        let accessClaims = token.accessToken.jwtPayload(as: CodexAccessClaims.self)
        let idClaims = token.idToken?.jwtPayload(as: CodexIDClaims.self)
        let accountID = accessClaims?.auth?.chatgptAccountID
        let email = idClaims?.email ?? "Codex Account"
        return (email, .oauth(OAuthTokens(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: token.expiry,
            extras: accountID.map { ["chatgpt_account_id": $0] } ?? [:]
        )))
    }
}

package struct AntigravityLogin: ProviderLogin {
    package static let clientID = OAuthClients.antigravityClientID
    package static let clientSecret = OAuthClients.antigravityClientSecret
    package var http: any HTTPClient = URLSessionHTTPClient()
    package var makeServer: OAuthCallbackServerFactory

    package init(http: any HTTPClient = URLSessionHTTPClient(), makeServer: @escaping OAuthCallbackServerFactory) {
        self.http = http
        self.makeServer = makeServer
    }

    package func login(prompt: @Sendable (LoginPrompt) async -> Void, pastedCode: AsyncStream<String>) async throws -> (label: String, credential: AccountCredential) {
        let pkce = PKCE.generate()
        let server = try await makeServer(pkce.verifier, 51121, "/oauth-callback")
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: server.redirectURI),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile https://www.googleapis.com/auth/cclog https://www.googleapis.com/auth/experimentsandconfigs"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.verifier),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        guard let url = components.url else { throw LoginError.invalidResponse }
        await prompt(.browser(url, acceptsPastedCode: true))
        do {
            let input = try await waitForAuthorizationInput(server: server, pastedCode: pastedCode)
            let code = try authorizationCode(from: input, expectedState: pkce.verifier, requireState: true)
            let response = try await LoginHTTP.postForm(URL(string: "https://oauth2.googleapis.com/token")!, fields: [
                "client_id": Self.clientID,
                "client_secret": Self.clientSecret,
                "code": code,
                "grant_type": "authorization_code",
                "redirect_uri": server.redirectURI,
                "code_verifier": pkce.verifier
            ], using: http)
            let token = try LoginHTTP.decode(OAuthTokenResponse.self, from: response)
            let userInfoURL = URL(string: "https://www.googleapis.com/oauth2/v1/userinfo?alt=json")!
            let userInfo = try await LoginHTTP.get(userInfoURL, bearerToken: token.accessToken, using: http)
            let label = (try? LoginHTTP.decode(GoogleUserInfo.self, from: userInfo).email) ?? "Google Account"
            return (label, .oauth(OAuthTokens(
                accessToken: token.accessToken,
                refreshToken: token.refreshToken,
                expiresAt: token.expiry
            )))
        } catch {
            server.cancel()
            throw error
        }
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

private struct ClaudeProfileResponse: Decodable {
    package struct Account: Decodable { let email: String? }
    package let account: Account?
    package let email: String?
}

private struct GoogleUserInfo: Decodable { let email: String? }

private struct CodexDeviceStart: Decodable {
    package let deviceAuthID: String
    package let userCode: String
    package let intervalValue: TimeInterval
    package enum CodingKeys: String, CodingKey {
        case deviceAuthID = "device_auth_id"
        case userCode = "user_code"
        case intervalValue = "interval"
    }
    package var interval: TimeInterval { intervalValue }

    package init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        deviceAuthID = try values.decode(String.self, forKey: .deviceAuthID)
        userCode = try values.decode(String.self, forKey: .userCode)
        if let interval = try? values.decode(TimeInterval.self, forKey: .intervalValue) {
            intervalValue = interval
        } else if let interval = try? values.decode(String.self, forKey: .intervalValue), let number = TimeInterval(interval) {
            intervalValue = number
        } else {
            intervalValue = 5
        }
    }
}

private struct CodexDeviceToken: Decodable {
    package let authorizationCode: String
    package let codeVerifier: String
    package enum CodingKeys: String, CodingKey {
        case authorizationCode = "authorization_code"
        case codeVerifier = "code_verifier"
    }
}

private struct CodexAccessClaims: Decodable {
    package struct Auth: Decodable {
        package let chatgptAccountID: String?
        package enum CodingKeys: String, CodingKey { case chatgptAccountID = "chatgpt_account_id" }
    }
    package let auth: Auth?
    package enum CodingKeys: String, CodingKey { case auth = "https://api.openai.com/auth" }
}

private struct CodexIDClaims: Decodable { let email: String? }

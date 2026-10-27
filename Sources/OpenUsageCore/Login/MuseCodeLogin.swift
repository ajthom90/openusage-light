import Foundation

/// Signs in to Muse Code with Meta's standard device flow: the app shows a code and a link, the user
/// approves it in a browser, and the app receives a sign-in token. The token is stored in this app's own
/// vault. The account is named after the signed-in Meta account's email when it reports one.
package struct MuseCodeLogin: ProviderLogin {
    package static let clientID = OAuthClients.museCodeClientID
    /// Meta's endpoints end in a slash, and the server answers the slashless form with an error, so these
    /// are written out whole rather than built with `appendingPathComponent`, which drops it.
    package static let authorizationURL = URL(string: "https://auth.meta.com/oidc/device/authorization/")!
    package static let tokenURL = URL(string: "https://auth.meta.com/oidc/device/token/")!
    package var http: any HTTPClient = URLSessionHTTPClient()

    package func login(prompt: @Sendable (LoginPrompt) async -> Void, pastedCode: AsyncStream<String>) async throws -> (label: String, credential: AccountCredential) {
        let start = try await LoginHTTP.postForm(Self.authorizationURL, fields: [
            "client_id": Self.clientID
        ], using: http)
        let device = try LoginHTTP.decode(MetaDeviceCode.self, from: start)
        guard let verificationURL = URL(string: device.verificationURIComplete ?? device.verificationURI),
              verificationURL.scheme == "https" else {
            throw LoginError.invalidResponse
        }
        await prompt(.deviceCode(userCode: device.userCode, verificationURL: verificationURL))
        let token: MetaTokenResponse = try await DeviceCodePoller.poll(
            interval: device.interval ?? 5,
            expiresIn: TimeInterval(device.expiresIn)
        ) { [http] in
            let response = try await LoginHTTP.postForm(Self.tokenURL, fields: [
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "client_id": Self.clientID,
                "device_code": device.deviceCode
            ], using: http)
            if (200..<300).contains(response.statusCode) {
                return .complete(try LoginHTTP.decode(MetaTokenResponse.self, from: response))
            }
            let error = LoginHTTP.jsonObject(response)["error"] ?? ""
            if error == "authorization_pending" { return DeviceCodePollResult<MetaTokenResponse>.pending }
            if error == "slow_down" { return DeviceCodePollResult<MetaTokenResponse>.slowDown }
            if error == "expired_token" { return DeviceCodePollResult<MetaTokenResponse>.failed("Meta device sign-in expired.") }
            return DeviceCodePollResult<MetaTokenResponse>.failed("Meta device sign-in failed.")
        }
        return (await accountLabel(for: token.accessToken), .oauth(OAuthTokens(accessToken: token.accessToken)))
    }

    /// The signed-in account's email, or "Muse Code" when the account does not report one.
    private func accountLabel(for token: String) async -> String {
        guard let response = try? await MuseCodeUsageClient(http: http).fetchSubscription(token: token),
              (200..<300).contains(response.statusCode),
              let email = ProviderParse.jsonObject(response.body)?["user_email"] as? String,
              !email.isEmpty else { return ProviderKind.musecode.displayName }
        return email
    }
}

private struct MetaDeviceCode: Decodable {
    package let deviceCode: String
    package let userCode: String
    package let verificationURI: String
    package let verificationURIComplete: String?
    package let expiresIn: Int
    package let interval: TimeInterval?
    package enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case verificationURIComplete = "verification_uri_complete"
        case expiresIn = "expires_in"
        case interval
    }
}

/// Meta's token answer carries only the token and its type: no refresh token and no expiry.
private struct MetaTokenResponse: Decodable {
    package let accessToken: String
    package enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

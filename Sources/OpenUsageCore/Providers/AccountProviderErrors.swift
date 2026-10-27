import Foundation

package struct ClaudeOAuthConfig: Hashable, Sendable {
    package var usageURL: URL
    package var refreshURL: URL
    package var clientID: String
}

package struct ClaudeOAuth: Hashable, Sendable {
    package var accessToken: String
    package var refreshToken: String?
    package var expiresAt: Double?
    package var subscriptionType: String?
    package var rateLimitTier: String?
}

package enum ClaudeAuthError: Error, LocalizedError, Equatable {
    case sessionExpired
    case tokenExpired

    package var errorDescription: String? {
        "Claude sign-in expired. Add the account again."
    }
}

package enum CodexAuthError: Error, LocalizedError, Equatable {
    case notLoggedIn
    case sessionExpired
    case tokenConflict
    case tokenRevoked
    case tokenExpired
    case usageAPIKey
    case invalidAuthPayload

    package var errorDescription: String? {
        "Codex sign-in expired. Add the account again."
    }
}

package enum CursorAuthError: Error, LocalizedError, Equatable {
    case notLoggedIn
    case sessionExpired
    case tokenExpired

    package var errorDescription: String? {
        "Cursor sign-in expired. Add the account again."
    }
}

package enum GrokAuthError: Error, LocalizedError, Equatable {
    case notLoggedIn
    case invalidAuth
    case expired

    package var errorDescription: String? {
        "Grok sign-in expired. Add the account again."
    }
}

package enum OpenCodeUsageError: Error, LocalizedError, Equatable {
    case connectionFailed
    case invalidResponse
    case requestFailed(Int)

    package var errorDescription: String? {
        switch self {
        case .connectionFailed: ProviderUsageErrorText.connectionFailed
        case .invalidResponse: ProviderUsageErrorText.invalidResponse
        case .requestFailed(let status): ProviderUsageErrorText.requestFailed(statusCode: status)
        }
    }
}

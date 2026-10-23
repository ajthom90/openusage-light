import Foundation

/// Quota-call failures for an Antigravity account. Token-refresh failures stay `LoginError`.
enum AntigravityError: Error, LocalizedError, Equatable {
    /// Cloud Code rejected the token (401/403).
    case authExpired
    /// Every Cloud Code host was unreachable or answered with a non-auth error.
    case unavailable
    /// A 2xx body that isn't a quota summary.
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .authExpired:
            return "Antigravity sign-in expired. Add the account again."
        case .unavailable:
            return "Antigravity usage is temporarily unavailable. Try again shortly."
        case .invalidResponse:
            return ProviderUsageErrorText.invalidResponse
        }
    }
}

import Foundation

enum ErrorCategory: String, Sendable, CaseIterable, Codable {
    case notLoggedIn = "not_logged_in"
    case authExpired = "auth_expired"
    case authInvalid = "auth_invalid"
    case credentialAccess = "credential_access"
    case network
    case decoding
    case http4xx
    case http5xx
    case rateLimited
    case notAvailable = "not_available"
    case other

    static func http(_ statusCode: Int) -> ErrorCategory {
        switch statusCode {
        case 429: .rateLimited
        case 400..<500: .http4xx
        case 500..<600: .http5xx
        default: .other
        }
    }
}

protocol CategorizedError: Error {
    var errorCategory: ErrorCategory { get }
}

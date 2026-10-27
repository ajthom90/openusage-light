import Foundation

package enum LoginError: LocalizedError, Sendable {
    case cancelled
    case invalidResponse
    case requestFailed(Int)
    case missingField(String)
    case invalidState
    case invalidCode

    package var errorDescription: String? {
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

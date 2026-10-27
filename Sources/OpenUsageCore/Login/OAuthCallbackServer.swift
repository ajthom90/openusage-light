import Foundation

/// A listener on the user's own machine that receives the browser's redirect at the end of a sign-in. The
/// Mac uses Apple's network framework; Windows uses sockets. The sign-in code only needs these three things.
package protocol OAuthCallbackServer: AnyObject, Sendable {
    /// The address to give the provider as the redirect, e.g. `http://localhost:1455/auth/callback`.
    var redirectURI: String { get }
    /// Waits for the browser to arrive with the authorization code.
    func waitForCode() async throws -> String
    func cancel()
}

/// Starts a listener for `state` on `port` (any free port when `nil`) answering at `path`.
package typealias OAuthCallbackServerFactory = @Sendable (_ state: String, _ port: UInt16?, _ path: String) async throws -> any OAuthCallbackServer

package enum LoopbackCallbackError: LocalizedError, Sendable {
    case listenerFailed(String)
    case invalidRequest
    case stateMismatch
    case cancelled
    case authorization(String)

    package var errorDescription: String? {
        switch self {
        case .listenerFailed(let detail): "Could not start the sign-in callback: \(detail)"
        case .invalidRequest: "The sign-in callback request was invalid."
        case .stateMismatch: "The sign-in response did not match this request."
        case .cancelled: "Sign-in was cancelled."
        case .authorization(let error): "Authorization failed: \(error)"
        }
    }
}

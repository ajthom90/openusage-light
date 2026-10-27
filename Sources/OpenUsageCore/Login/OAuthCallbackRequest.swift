import Foundation

/// What a redirect listener does with one HTTP request from the browser: the rules are the same on every
/// platform, so they live here and each platform's listener only moves the bytes.
package enum OAuthCallbackRequest {
    package struct Outcome {
        package let status: Int
        /// The sentence shown on the page the browser lands on.
        package let message: String
        /// `.success` with the code, or why the sign-in cannot continue.
        package let result: Result<String, any Error>

        package init(status: Int, message: String, result: Result<String, any Error>) {
            self.status = status
            self.message = message
            self.result = result
        }
    }

    /// A request that could not even be read.
    package static let unreadable = Outcome(
        status: 400, message: "Sign-in failed.", result: .failure(LoopbackCallbackError.invalidRequest)
    )

    package static func evaluate(_ request: String, path: String, state: String) -> Outcome {
        guard let line = request.components(separatedBy: "\r\n").first,
              let target = line.split(separator: " ").dropFirst().first,
              line.hasPrefix("GET ") else {
            return Outcome(status: 405, message: "Only GET is supported.", result: .failure(LoopbackCallbackError.invalidRequest))
        }
        guard let url = URL(string: "http://localhost\(target)"), url.path == path else {
            return Outcome(status: 404, message: "Sign-in callback not found.", result: .failure(LoopbackCallbackError.invalidRequest))
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        guard items?.first(where: { $0.name == "state" })?.value == state else {
            return Outcome(status: 400, message: "Sign-in state did not match.", result: .failure(LoopbackCallbackError.stateMismatch))
        }
        if let error = items?.first(where: { $0.name == "error" })?.value {
            return Outcome(status: 400, message: "Sign-in failed.", result: .failure(LoopbackCallbackError.authorization(error)))
        }
        guard let code = items?.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            return Outcome(status: 400, message: "Authorization code was missing.", result: .failure(LoopbackCallbackError.invalidRequest))
        }
        return Outcome(status: 200, message: "Sign-in complete. You may close this page.", result: .success(code))
    }

    /// The complete HTTP response for `outcome`.
    package static func response(for outcome: Outcome) -> Data {
        let body = Data("<!doctype html><title>OpenUsage Light</title><p>\(outcome.message)</p>".utf8)
        let head = "HTTP/1.1 \(outcome.status) \(outcome.status == 200 ? "OK" : "Error")\r\n"
            + "Content-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}

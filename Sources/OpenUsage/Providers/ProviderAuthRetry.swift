import Foundation

enum ProviderAuthRetry {
    static func isAuthFailure(_ response: HTTPResponse) -> Bool {
        response.statusCode == 401 || response.statusCode == 403
    }

    static func requireSuccess(
        _ response: HTTPResponse,
        authExpired: Error,
        requestFailed: (Int) -> Error
    ) throws {
        if isAuthFailure(response) { throw authExpired }
        guard (200..<300).contains(response.statusCode) else {
            throw requestFailed(response.statusCode)
        }
    }
}

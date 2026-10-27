import Foundation

package struct CursorSession: Equatable, Sendable {
    package var userID: String
    package var sessionToken: String
}

package struct CursorUsageClient: Sendable {
    package static let usageURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
    package static let grokBotUsageURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus")!
    package static let planURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetPlanInfo")!
    package static let refreshURL = URL(string: "https://api2.cursor.sh/oauth/token")!
    package static let creditsURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCreditGrantsBalance")!
    package static let restUsageURL = URL(string: "https://cursor.com/api/usage")!
    package static let usageSummaryURL = URL(string: "https://cursor.com/api/usage-summary")!
    package static let stripeURL = URL(string: "https://cursor.com/api/auth/stripe")!
    package static let clientID = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"

    package var http: any HTTPClient

    package init(http: any HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    package func refreshToken(_ refreshToken: String) async throws -> HTTPResponse {
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "client_id": Self.clientID,
            "refresh_token": refreshToken
        ]
        return try await http.send(HTTPRequest(
            method: "POST",
            url: Self.refreshURL,
            headers: ["Content-Type": "application/json"],
            body: try JSONSerialization.data(withJSONObject: body),
            timeout: 15
        ))
    }

    package func fetchUsage(accessToken: String) async throws -> HTTPResponse {
        try await connectPost(Self.usageURL, accessToken: accessToken)
    }

    package func fetchGrokBotUsage(accessToken: String) async throws -> HTTPResponse {
        try await connectPost(Self.grokBotUsageURL, accessToken: accessToken)
    }

    package func fetchPlan(accessToken: String) async throws -> HTTPResponse {
        try await connectPost(Self.planURL, accessToken: accessToken)
    }

    package func fetchCredits(accessToken: String) async throws -> HTTPResponse {
        try await connectPost(Self.creditsURL, accessToken: accessToken)
    }

    package func fetchRequestBasedUsage(accessToken: String) async throws -> HTTPResponse? {
        guard let session = Self.session(from: accessToken) else { return nil }
        var components = URLComponents(url: Self.restUsageURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "user", value: session.userID)]
        guard let url = components?.url else { return nil }

        return try await http.send(HTTPRequest(
            method: "GET",
            url: url,
            headers: ["Cookie": "WorkosCursorSessionToken=\(session.sessionToken)"],
            timeout: 10
        ))
    }

    package func fetchUsageSummary(accessToken: String) async throws -> HTTPResponse? {
        guard let session = Self.session(from: accessToken) else { return nil }
        return try await http.send(HTTPRequest(
            method: "GET",
            url: Self.usageSummaryURL,
            headers: ["Cookie": "WorkosCursorSessionToken=\(session.sessionToken)"],
            timeout: 10
        ))
    }

    package func fetchStripeBalance(accessToken: String) async throws -> HTTPResponse? {
        guard let session = Self.session(from: accessToken) else { return nil }
        return try await http.send(HTTPRequest(
            method: "GET",
            url: Self.stripeURL,
            headers: ["Cookie": "WorkosCursorSessionToken=\(session.sessionToken)"],
            timeout: 10
        ))
    }

    private func connectPost(_ url: URL, accessToken: String) async throws -> HTTPResponse {
        try await http.send(HTTPRequest(
            method: "POST",
            url: url,
            headers: [
                "Authorization": "Bearer \(accessToken)",
                "Content-Type": "application/json",
                "Connect-Protocol-Version": "1"
            ],
            body: Data("{}".utf8),
            timeout: 10
        ))
    }

    package static func session(from accessToken: String) -> CursorSession? {
        guard let subject = ProviderParse.jwtPayload(accessToken)?["sub"] as? String else { return nil }
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSubject.isEmpty else { return nil }
        let parts = trimmedSubject.split(separator: "|", omittingEmptySubsequences: false)
        let userID = String(parts.count > 1 ? parts[1] : parts[0])
        guard !userID.isEmpty else { return nil }
        return CursorSession(userID: userID, sessionToken: "\(userID)%3A%3A\(accessToken)")
    }
}

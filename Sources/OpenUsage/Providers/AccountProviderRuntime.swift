import Foundation

@MainActor
final class AccountProviderRuntime: ProviderRuntime {
    private(set) var account: Account
    private(set) var provider: Provider
    let vault: any CredentialVault
    let http: any HTTPClient
    let now: () -> Date
    /// Claude's plan from `/api/oauth/profile`, looked up once per access token. The in-app login never
    /// receives a plan, so the profile is the only source of it.
    private var claudePlan: (accessToken: String, plan: String)?
    /// Claude's reset-grants state, carried across refreshes (see `AccountProviderRuntime+ClaudeResets`).
    var claudeResetGrants = ClaudeResetGrantsState()
    /// The Codex credit each claim's idempotency key was matched to (see `AccountProviderRuntime+CodexResets`).
    var codexMatchedCreditIDs: [String: String] = [:]

    init(
        account: Account,
        vault: any CredentialVault,
        http: any HTTPClient = URLSessionHTTPClient(),
        now: @escaping () -> Date = Date.init
    ) {
        self.account = account
        self.vault = vault
        self.http = http
        self.now = now
        provider = Self.provider(for: account)
    }

    /// Picks up a rename without replacing the runtime.
    func update(_ account: Account) {
        self.account = account
        provider = Self.provider(for: account)
    }

    private static func provider(for account: Account) -> Provider {
        Provider(
            id: account.cardID,
            displayName: account.kind.displayName,
            icon: account.kind.iconSource,
            accountLabel: account.label,
            links: account.kind.links
        )
    }

    var widgetDescriptors: [WidgetDescriptor] {
        let prefix = account.cardID
        return switch account.kind {
        case .claude:
            [
                .percent(id: "\(prefix).session", provider: provider, title: "Session", sessionStartSignal: .missingResetDate),
                .percent(id: "\(prefix).weekly", provider: provider, title: "Weekly"),
                .percent(id: "\(prefix).sonnet", provider: provider, title: "Sonnet"),
                .percent(id: "\(prefix).fable", provider: provider, title: "Fable"),
                .boundedDollars(id: "\(prefix).extra", provider: provider, title: "Extra Usage", metricLabel: "Extra usage spent", limit: 100),
                Self.rateLimitResets(id: "\(prefix).rateLimitResets", provider: provider)
            ]
        case .codex:
            [
                .percent(id: "\(prefix).session", provider: provider, title: "Session"),
                .percent(id: "\(prefix).weekly", provider: provider, title: "Weekly"),
                .percent(id: "\(prefix).spark", provider: provider, title: "Spark"),
                .percent(id: "\(prefix).sparkWeekly", provider: provider, title: "Spark Weekly"),
                .combined(id: "\(prefix).credits", provider: provider, title: "Extra Usage", metricLabel: "Credits"),
                Self.rateLimitResets(id: "\(prefix).rateLimitResets", provider: provider)
            ]
        case .cursor:
            [
                .percent(id: "\(prefix).usage", provider: provider, title: "Total usage", metricLabel: "Total usage"),
                .percent(id: "\(prefix).auto", provider: provider, title: "Auto"),
                .percent(id: "\(prefix).api", provider: provider, title: "API"),
                .percent(id: "\(prefix).onDemand", provider: provider, title: "On-demand"),
                .percent(id: "\(prefix).grokBot", provider: provider, title: "Grok Bot usage")
            ]
        case .antigravity:
            [
                .percent(id: "\(prefix).geminiPro", provider: provider, title: "Session", sessionStartSignal: .zeroUsage),
                .percent(id: "\(prefix).geminiWeekly", provider: provider, title: "Weekly"),
                .percent(id: "\(prefix).argonWeekly", provider: provider, title: "Argon Weekly"),
                .percent(id: "\(prefix).claude", provider: provider, title: "Claude", sessionStartSignal: .zeroUsage),
                .percent(id: "\(prefix).claudeWeekly", provider: provider, title: "Claude Weekly")
            ]
        case .copilot:
            [
                .percent(id: "\(prefix).premium", provider: provider, title: "Credits", metricLabel: "Credits"),
                .values(id: "\(prefix).extra", provider: provider, title: "Extra Usage"),
                .boundedCount(id: "\(prefix).chat", provider: provider, title: "Chat", limit: 0, suffix: "messages"),
                .boundedCount(id: "\(prefix).completions", provider: provider, title: "Completions", limit: 0, suffix: "completions")
            ]
        case .grok:
            [
                .percent(id: "\(prefix).weekly", provider: provider, title: "Weekly limit"),
                .badge(id: "\(prefix).payAsYouGo", provider: provider, title: "Pay as you go")
            ]
        case .ollama:
            [
                .percent(id: "\(prefix).session", provider: provider, title: "Session"),
                .percent(id: "\(prefix).weekly", provider: provider, title: "Weekly"),
                .percent(id: "\(prefix).monthly", provider: provider, title: "Monthly"),
                .dollarBalance(id: "\(prefix).purchasedCredits", provider: provider, title: "Purchased Credits", valueWord: "left")
            ]
        case .opencodeGo:
            [
                .percent(id: "\(prefix).session", provider: provider, title: "Session", sessionStartSignal: .missingResetDate),
                .percent(id: "\(prefix).weekly", provider: provider, title: "Weekly"),
                .percent(id: "\(prefix).monthly", provider: provider, title: "Monthly")
            ]
        case .openrouter:
            [
                .dollarBalance(id: "\(prefix).balance", provider: provider, title: "Balance", valueWord: "left"),
                .values(id: "\(prefix).today", provider: provider, title: "Today"),
                .values(id: "\(prefix).week", provider: provider, title: "This Week"),
                .values(id: "\(prefix).month", provider: provider, title: "This Month")
            ]
        case .zai:
            [
                .percent(id: "\(prefix).session", provider: provider, title: "Session"),
                .percent(id: "\(prefix).weekly", provider: provider, title: "Weekly"),
                .boundedCount(id: "\(prefix).webSearches", provider: provider, title: "Web Searches", limit: 0, suffix: "searches")
            ]
        }
    }

    /// The row behind each Claude and Codex card's resets popover, where the account's resets are claimed.
    private static func rateLimitResets(id: String, provider: Provider) -> WidgetDescriptor {
        .values(id: id, provider: provider, title: "Rate Limit Resets", metricLabel: "Rate Limit Resets",
                traySuffix: "resets", showsResetExpiries: true)
    }

    /// The resets popover's claim seam for this account, or `nil` for providers without reset claims.
    /// Claude always spends the grant Anthropic names next, so the picked node's expiry only matters to
    /// Codex.
    func resetClaimService(
        refreshAccount: @escaping @MainActor () async -> WidgetDataStore.RefreshOutcome
    ) -> ResetClaimService? {
        switch account.kind {
        case .claude:
            let status = claudeResetGrants.check?.status
            return ResetClaimService(
                accountID: account.cardID,
                isClaimable: status?.claimableGrantID != nil,
                confirmDetail: status?.confirmDetail,
                claimReset: { [self] _, redeemRequestID in await claimClaudeResetGrant(redeemRequestID: redeemRequestID) },
                refreshAccount: refreshAccount
            )
        case .codex:
            return ResetClaimService(
                accountID: account.cardID,
                isClaimable: true,
                confirmDetail: nil,
                claimReset: { [self] expiry, redeemRequestID in
                    await claimCodexResetCredit(expiringAt: expiry, redeemRequestID: redeemRequestID)
                },
                refreshAccount: refreshAccount
            )
        case .cursor, .antigravity, .copilot, .grok, .ollama, .opencodeGo, .openrouter, .zai:
            return nil
        }
    }

    func refresh() async -> ProviderSnapshot {
        do {
            let result = try await refresh(try await loadCredential())
            return ProviderSnapshot.make(provider: provider, plan: result.plan, lines: result.lines, refreshedAt: Date())
        } catch {
            return ProviderSnapshot.error(provider: provider, error: error)
        }
    }

    /// The account's own credential from the vault; the only credential a refresh or claim ever uses.
    func loadCredential() async throws -> AccountCredential {
        guard let credential = try await loadOffMainActor({ [vault, account] in try vault.load(account.id) }) else {
            throw LoginError.cancelled
        }
        return credential
    }

    private func refresh(_ credential: AccountCredential) async throws -> (plan: String?, lines: [MetricLine]) {
        switch account.kind {
        case .claude: try await refreshClaude(credential)
        case .codex: try await refreshCodex(credential)
        case .cursor: try await refreshCursor(credential)
        case .antigravity: try await refreshAntigravity(credential)
        case .copilot: try await refreshCopilot(credential)
        case .grok: try await refreshGrok(credential)
        case .ollama: try await refreshOllama(credential)
        case .opencodeGo: try await refreshOpenCode(credential)
        case .openrouter: try await refreshOpenRouter(credential)
        case .zai: try await refreshZAI(credential)
        }
    }

    static let claudeConfig = ClaudeOAuthConfig(
        usageURL: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
        refreshURL: URL(string: "https://platform.claude.com/v1/oauth/token")!,
        clientID: ClaudeLogin.clientID
    )

    /// The account's Claude tokens, refreshed and saved back to the vault first when they've expired.
    func claudeTokens(_ credential: AccountCredential) async throws -> OAuthTokens {
        guard case .oauth(var tokens) = credential else { throw LoginError.invalidResponse }
        if tokens.expiresAt.map({ $0 <= now() }) == true, let refreshToken = tokens.refreshToken {
            let response = try await ClaudeUsageClient(httpClient: http).refreshToken(refreshToken, config: Self.claudeConfig)
            guard (200..<300).contains(response.statusCode) else { throw ClaudeUsageError.requestFailed(response.statusCode) }
            let refreshed = try JSONDecoder().decode(ClaudeRefreshResponse.self, from: response.body)
            tokens.accessToken = refreshed.accessToken
            if let refresh = refreshed.refreshToken { tokens.refreshToken = refresh }
            tokens.expiresAt = refreshed.expiresIn.map { now().addingTimeInterval($0) }
            try await save(.oauth(tokens))
        }
        return tokens
    }

    private func refreshClaude(_ credential: AccountCredential) async throws -> (String?, [MetricLine]) {
        let tokens = try await claudeTokens(credential)
        let config = Self.claudeConfig
        let response = try await ClaudeUsageClient(httpClient: http).fetchUsage(accessToken: tokens.accessToken, config: config)
        let oauth = ClaudeOAuth(
            accessToken: tokens.accessToken, refreshToken: tokens.refreshToken,
            expiresAt: tokens.expiresAt?.timeIntervalSince1970,
            subscriptionType: tokens.extras["subscription_type"], rateLimitTier: tokens.extras["rate_limit_tier"]
        )
        var mapped = try ClaudeUsageMapper.mapUsageResponse(response, credentials: oauth)
        if let resets = await claudeResetGrantsLine(accessToken: tokens.accessToken) {
            mapped.lines.append(resets)
        }
        return (await claudeLivePlan(oauth, config: config) ?? mapped.plan, mapped.lines)
    }

    private func claudeLivePlan(_ oauth: ClaudeOAuth, config: ClaudeOAuthConfig) async -> String? {
        if let claudePlan, claudePlan.accessToken == oauth.accessToken { return claudePlan.plan }
        do {
            let response = try await ClaudeUsageClient(httpClient: http).fetchProfile(accessToken: oauth.accessToken, config: config)
            let profile = try ClaudeUsageClient.decodeProfile(response)
            guard let plan = ClaudeUsageMapper.formatLivePlan(profile: profile, credentials: oauth) else { return nil }
            claudePlan = (oauth.accessToken, plan)
            return plan
        } catch {
            AppLog.warn(LogTag.plugin("claude"), "plan lookup failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// The account's Codex tokens, refreshed and saved back to the vault first when they've expired.
    func codexTokens(_ credential: AccountCredential) async throws -> OAuthTokens {
        guard case .oauth(var tokens) = credential else { throw LoginError.invalidResponse }
        if tokens.expiresAt.map({ $0 <= now() }) == true, let refreshToken = tokens.refreshToken {
            let refreshed = try await CodexUsageClient(http: http).refreshToken(refreshToken)
            tokens.accessToken = refreshed.accessToken
            if let refresh = refreshed.refreshToken { tokens.refreshToken = refresh }
            tokens.expiresAt = ProviderParse.number(ProviderParse.jwtPayload(refreshed.accessToken)?["exp"])
                .map(Date.init(timeIntervalSince1970:))
            try await save(.oauth(tokens))
        }
        return tokens
    }

    private func refreshCodex(_ credential: AccountCredential) async throws -> (String?, [MetricLine]) {
        let tokens = try await codexTokens(credential)
        let accountID = tokens.extras["chatgpt_account_id"]
        let response = try await CodexUsageClient(http: http).fetchUsage(accessToken: tokens.accessToken, accountID: accountID)
        let resetCredits = await codexResetCredits(after: response, accessToken: tokens.accessToken, accountID: accountID)
        let mapped = try CodexUsageMapper.mapUsageResponse(response, resetCredits: resetCredits, now: now())
        return (mapped.plan, mapped.lines)
    }

    private func refreshCopilot(_ credential: AccountCredential) async throws -> (String?, [MetricLine]) {
        guard case .oauth(let tokens) = credential else { throw LoginError.invalidResponse }
        let response = try await CopilotUsageClient(http: http).fetchUsage(token: tokens.accessToken)
        let mapped = try CopilotUsageMapper.map(response)
        return (mapped.plan, mapped.lines)
    }

    private func refreshGrok(_ credential: AccountCredential) async throws -> (String?, [MetricLine]) {
        guard case .oauth(var tokens) = credential else { throw LoginError.invalidResponse }
        let client = GrokUsageClient(httpClient: http)
        if tokens.expiresAt.map({ $0 <= Date() }) == true, let refreshToken = tokens.refreshToken {
            let response = try await client.refreshToken(refreshToken, clientID: GrokLogin.clientID)
            guard (200..<300).contains(response.statusCode), let refreshed = client.decodeRefreshResponse(response) else {
                throw GrokUsageError.requestFailed(response.statusCode)
            }
            tokens.accessToken = refreshed.accessToken
            if let refresh = refreshed.refreshToken { tokens.refreshToken = refresh }
            tokens.expiresAt = refreshed.expiresIn.map { Date().addingTimeInterval(max(0, $0 - 300)) }
            try await save(.oauth(tokens))
        }
        let usage = try await client.fetchCreditsConfig(accessToken: tokens.accessToken)
        let mapped = try GrokUsageMapper.mapCreditsConfig(usage)
        let settings = try? await client.fetchSettings(accessToken: tokens.accessToken)
        return (settings.flatMap(GrokUsageMapper.planName(from:)), mapped.lines)
    }

    private func refreshCursor(_ credential: AccountCredential) async throws -> (String?, [MetricLine]) {
        guard case .oauth(var tokens) = credential else { throw LoginError.invalidResponse }
        let client = CursorUsageClient(http: http)
        if tokens.expiresAt.map({ $0 <= Date() }) == true, let refreshToken = tokens.refreshToken {
            let response = try await client.refreshToken(refreshToken)
            let body = ProviderParse.jsonObject(response.body)
            if body?["shouldLogout"] as? Bool == true { throw CursorAuthError.sessionExpired }
            guard (200..<300).contains(response.statusCode),
                  let accessToken = body?["access_token"] as? String,
                  !accessToken.isEmpty
            else { throw CursorAuthError.tokenExpired }
            tokens.accessToken = accessToken
            if let rotated = body?["refresh_token"] as? String { tokens.refreshToken = rotated }
            tokens.expiresAt = ProviderParse.number(body?["expires_in"])
                .map { Date().addingTimeInterval(max(0, $0 - 300)) }
            try await save(.oauth(tokens))
        }
        let usageResponse = try await client.fetchUsage(accessToken: tokens.accessToken)
        guard (200..<300).contains(usageResponse.statusCode),
              let usage = ProviderParse.jsonObject(usageResponse.body)?["usage"] as? [String: Any]
        else {
            throw CursorUsageError.invalidResponse
        }
        let planResponse = try? await client.fetchPlan(accessToken: tokens.accessToken)
        let planBody = planResponse.flatMap { response in
            (200..<300).contains(response.statusCode) ? ProviderParse.jsonObject(response.body) : nil
        }
        let planName = (planBody?["planInfo"] as? [String: Any])?["planName"] as? String
        let creditsResponse = try? await client.fetchCredits(accessToken: tokens.accessToken)
        let credits = creditsResponse.flatMap { response in
            (200..<300).contains(response.statusCode) ? ProviderParse.jsonObject(response.body) : nil
        }
        let stripeResponse = try? await client.fetchStripeBalance(accessToken: tokens.accessToken)
        let stripeBody = stripeResponse.flatMap { response in
            (200..<300).contains(response.statusCode) ? ProviderParse.jsonObject(response.body) : nil
        }
        var mapped = try CursorUsageMapper.mapUsage(
            usage: usage,
            planName: planName,
            creditGrants: credits,
            stripeBalanceCents: CursorUsageMapper.stripeBalanceCents(from: stripeBody)
        )
        if let response = try? await client.fetchUsageSummary(accessToken: tokens.accessToken),
           (200..<300).contains(response.statusCode),
           let summary = ProviderParse.jsonObject(response.body),
           CursorUsageSummaryMapper.hasUsableSummaryPayload(summary) {
            CursorUsageSummaryMapper.appendMissingOnDemand(from: summary, to: &mapped.lines)
        }
        if let grok = try? await client.fetchGrokBotUsage(accessToken: tokens.accessToken),
           let body = ProviderParse.jsonObject(grok.body),
           let line = CursorUsageMapper.mapGrokBotUsage(body) {
            mapped.lines.append(line)
        }
        return (mapped.plan, mapped.lines)
    }

    private func refreshAntigravity(_ credential: AccountCredential) async throws -> (String?, [MetricLine]) {
        guard case .oauth(var tokens) = credential else { throw LoginError.invalidResponse }
        if tokens.expiresAt.map({ $0 <= Date() }) == true, let refreshToken = tokens.refreshToken {
            let response = try await http.send(HTTPRequest(
                method: "POST",
                url: URL(string: "https://oauth2.googleapis.com/token")!,
                headers: ["Content-Type": "application/x-www-form-urlencoded"],
                body: Data([
                    "client_id=\(AntigravityLogin.clientID.urlFormEncoded)",
                    "client_secret=\(AntigravityLogin.clientSecret.urlFormEncoded)",
                    "refresh_token=\(refreshToken.urlFormEncoded)",
                    "grant_type=refresh_token"
                ].joined(separator: "&").utf8),
                timeout: 15
            ))
            guard (200..<300).contains(response.statusCode),
                  let body = ProviderParse.jsonObject(response.body),
                  let accessToken = body["access_token"] as? String
            else { throw LoginError.invalidResponse }
            tokens.accessToken = accessToken
            tokens.expiresAt = ProviderParse.number(body["expires_in"])
                .map { Date().addingTimeInterval(max(0, $0 - 300)) }
            try await save(.oauth(tokens))
        }
        let client = AntigravityUsageClient(http: http)
        let response = await client.cloudCodeAllHosts(
            path: AntigravityUsageClient.quotaSummaryPath,
            token: tokens.accessToken,
            userAgent: AntigravityUsageClient.clientUserAgent,
            body: [:],
            isComplete: AntigravityUsageMapper.isCompleteSummary
        )
        guard case .ok(let bodies) = response,
              let lines = AntigravityUsageMapper.parseQuotaSummaries(bodies)
        else { throw LoginError.invalidResponse }
        let planResponse = await client.loadCodeAssist(token: tokens.accessToken)
        let plan: String?
        if case .ok(let data) = planResponse { plan = AntigravityUsageMapper.parseLoadCodeAssistPlan(data) }
        else { plan = nil }
        return (plan, lines)
    }

    private func refreshOllama(_ credential: AccountCredential) async throws -> (String?, [MetricLine]) {
        guard case .apiKey(let key) = credential else { throw LoginError.invalidResponse }
        let client = OllamaUsageClient(http: http)
        let balance = try await client.fetchBalance(apiKey: key)
        let account = try? await client.fetchAccount(apiKey: key)
        let mapped = try OllamaUsageMapper.map(balanceBody: balance.body, accountBody: account?.body)
        return (mapped.plan.name, mapped.lines)
    }

    private func refreshOpenCode(_ credential: AccountCredential) async throws -> (String?, [MetricLine]) {
        guard case .apiKey(let key) = credential else { throw LoginError.invalidResponse }
        let response = try await OpenCodeUsageClient(http: http).fetchUsage(apiKey: key)
        return (OpenCodeUsageMapper.plan, try OpenCodeUsageMapper.meterLines(response))
    }

    private func refreshOpenRouter(_ credential: AccountCredential) async throws -> (String?, [MetricLine]) {
        guard case .apiKey(let key) = credential else { throw LoginError.invalidResponse }
        let client = OpenRouterUsageClient(http: http)
        let credits = try? await client.fetchCredits(apiKey: key)
        let keyResponse = try? await client.fetchKey(apiKey: key)
        var lines: [MetricLine] = []
        if let credits, let data = OpenRouterUsageMapper.dataObject(credits.body) {
            lines += OpenRouterUsageMapper.creditsLines(from: data)
        }
        var plan: String?
        if let keyResponse, let data = OpenRouterUsageMapper.dataObject(keyResponse.body) {
            let mapped = OpenRouterUsageMapper.keyMetrics(from: data)
            plan = mapped.plan
            lines += mapped.lines
        }
        guard !lines.isEmpty else { throw LoginError.invalidResponse }
        return (plan, lines)
    }

    private func refreshZAI(_ credential: AccountCredential) async throws -> (String?, [MetricLine]) {
        guard case .apiKey(let key) = credential else { throw LoginError.invalidResponse }
        let client = ZAIUsageClient(http: http)
        let quota = try await client.fetchQuota(apiKey: key)
        let subscription = try? await client.fetchSubscription(apiKey: key)
        let mapped = try ZAIUsageMapper.map(quotaBody: quota.body, subscriptionBody: subscription?.body)
        return (mapped.plan, mapped.lines)
    }

    private func save(_ credential: AccountCredential) async throws {
        try await loadOffMainActor { [vault, account] in try vault.save(credential, for: account.id) }
    }
}

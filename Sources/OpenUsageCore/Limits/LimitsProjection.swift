import Foundation

/// Turns the provider snapshots the app already holds into the stable `LimitsEnvelope`.
///
/// The public resource keys (`totalUsage`, `premiumCredits`, `geminiSession`, …) are declared here, not
/// derived from the dashboard's row ids, so reworking a dashboard row can never rename a field a script
/// depends on. A resource the provider did not report is omitted rather than invented as zero, and
/// notices that are only text (a badge, a plain message) are not limits and are left out.
package enum LimitsProjection {
    package struct Entry {
        package let account: Account
        /// The latest good snapshot, or `nil` when the account has never produced one.
        package let snapshot: ProviderSnapshot?
        /// The snapshot line label behind each dashboard row, by the row's id without the account's
        /// prefix (`session`, `extra`, …). The rows live with the dashboard, so the caller supplies them.
        package let metricLabels: [String: String]

        package init(account: Account, snapshot: ProviderSnapshot?, metricLabels: [String: String]) {
            self.account = account
            self.snapshot = snapshot
            self.metricLabels = metricLabels
        }
    }

    package static func envelope(
        entries: [Entry],
        failures: [LimitsEnvelope.Failure],
        order: [String],
        now: Date,
        freshFor ttl: TimeInterval
    ) -> LimitsEnvelope {
        var providers: [String: LimitsEnvelope.Provider] = [:]
        for entry in entries {
            guard let snapshot = entry.snapshot else { continue }
            let resources = resources(for: entry, snapshot: snapshot)
            let expiresAt = snapshot.refreshedAt.addingTimeInterval(ttl)
            providers[entry.account.cardID] = LimitsEnvelope.Provider(
                provider: entry.account.kind.rawValue,
                displayName: entry.account.kind.displayName,
                account: entry.account.label,
                plan: snapshot.plan,
                fetchedAt: snapshot.refreshedAt,
                expiresAt: expiresAt,
                stale: now >= expiresAt,
                resources: resources
            )
        }
        return LimitsEnvelope(
            generatedAt: now,
            order: order.filter { providers[$0] != nil },
            providers: providers,
            errors: failures
        )
    }

    /// The dashboard row ids (without the account prefix) the document reads for a provider.
    package static func rowSuffixes(for kind: ProviderKind) -> [String] {
        (specs[kind] ?? []).map(\.suffix)
    }

    // MARK: - Resources

    private static func resources(for entry: Entry, snapshot: ProviderSnapshot) -> [String: LimitsEnvelope.Resource] {
        var result: [String: LimitsEnvelope.Resource] = [:]
        for spec in specs[entry.account.kind] ?? [] {
            guard let label = entry.metricLabels[spec.suffix],
                  let line = snapshot.line(label: label),
                  let resource = resource(from: line, spec: spec) else { continue }
            result[spec.key] = resource
        }
        return result
    }

    private static func resource(from line: MetricLine, spec: Spec) -> LimitsEnvelope.Resource? {
        switch line {
        case .progress(_, let used, let limit, let format, let resetsAt, let periodDurationMs, _):
            guard used.isFinite, limit.isFinite else { return nil }
            var resource = LimitsEnvelope.Resource(kind: .consumption, unit: unit(for: format), used: used)
            if limit > 0 {
                resource.limit = limit
                resource.remaining = max(limit - used, 0)
                resource.utilization = min(max(used / limit, 0), 1)
            }
            resource.resetsAt = resetsAt
            resource.windowSeconds = periodDurationMs.map { $0 / 1000 }
            return resource
        case .values(_, let values, _, let expiriesAt):
            let value = spec.pick.map { kind in values.first { $0.kind == kind } } ?? values.first
            guard let value, value.number.isFinite else { return nil }
            var resource = LimitsEnvelope.Resource(kind: spec.role, unit: spec.unit ?? unit(for: value))
            switch spec.role {
            case .consumption: resource.used = value.number
            case .balance: resource.available = value.number
            }
            if !expiriesAt.isEmpty { resource.expiries = expiriesAt }
            return resource
        case .text, .badge:
            return nil
        }
    }

    private static func unit(for format: ProgressFormat) -> String {
        switch format {
        case .percent: "percent"
        case .dollars: "usd"
        case .count(let suffix): suffix.isEmpty ? "count" : suffix
        }
    }

    private static func unit(for value: MetricValue) -> String {
        switch value.kind {
        case .percent: "percent"
        case .dollars: "usd"
        case .count: value.label.flatMap { $0.isEmpty ? nil : $0 } ?? "count"
        }
    }

    // MARK: - Public keys

    private struct Spec {
        package let suffix: String
        package let key: String
        package var role: LimitsEnvelope.Resource.Kind = .consumption
        /// For a row carrying several numbers: the kind to report. `nil` takes the first.
        package var pick: MetricKind?
        /// Overrides the unit the value's own label would give ("available" names a state, not a unit).
        package var unit: String?
    }

    private static let specs: [ProviderKind: [Spec]] = [
        .claude: [
            Spec(suffix: "session", key: "session"),
            Spec(suffix: "weekly", key: "weekly"),
            Spec(suffix: "sonnet", key: "sonnet"),
            Spec(suffix: "fable", key: "fable"),
            Spec(suffix: "extra", key: "extraUsage"),
            Spec(suffix: "rateLimitResets", key: "rateLimitResets", role: .balance, unit: "resets")
        ],
        .codex: [
            Spec(suffix: "session", key: "session"),
            Spec(suffix: "weekly", key: "weekly"),
            Spec(suffix: "spark", key: "spark"),
            Spec(suffix: "sparkWeekly", key: "sparkWeekly"),
            Spec(suffix: "credits", key: "credits", role: .balance, pick: .count),
            Spec(suffix: "credits", key: "creditValue", role: .balance, pick: .dollars),
            Spec(suffix: "rateLimitResets", key: "rateLimitResets", role: .balance, unit: "resets")
        ],
        .cursor: [
            Spec(suffix: "usage", key: "totalUsage"),
            Spec(suffix: "auto", key: "autoUsage"),
            Spec(suffix: "api", key: "apiUsage"),
            Spec(suffix: "onDemand", key: "onDemand"),
            Spec(suffix: "grokBot", key: "grokBot"),
            Spec(suffix: "requests", key: "requests"),
            Spec(suffix: "credits", key: "credits", role: .balance)
        ],
        .antigravity: [
            Spec(suffix: "geminiPro", key: "geminiSession"),
            Spec(suffix: "geminiWeekly", key: "geminiWeekly"),
            Spec(suffix: "argonWeekly", key: "argonWeekly"),
            Spec(suffix: "claude", key: "nonGeminiSession"),
            Spec(suffix: "claudeWeekly", key: "nonGeminiWeekly")
        ],
        .copilot: [
            Spec(suffix: "premium", key: "premiumCredits"),
            Spec(suffix: "extra", key: "extraUsage"),
            Spec(suffix: "chat", key: "chat"),
            Spec(suffix: "completions", key: "completions")
        ],
        .grok: [
            Spec(suffix: "weekly", key: "weekly")
        ],
        .musecode: [
            Spec(suffix: "session", key: "session"),
            Spec(suffix: "weekly", key: "weekly")
        ],
        .ollama: [
            Spec(suffix: "session", key: "session"),
            Spec(suffix: "weekly", key: "weekly"),
            Spec(suffix: "monthly", key: "monthly"),
            Spec(suffix: "purchasedCredits", key: "purchasedCredits", role: .balance)
        ],
        .opencodeGo: [
            Spec(suffix: "session", key: "session"),
            Spec(suffix: "weekly", key: "weekly"),
            Spec(suffix: "monthly", key: "monthly")
        ],
        .openrouter: [
            Spec(suffix: "balance", key: "balance", role: .balance),
            Spec(suffix: "today", key: "today"),
            Spec(suffix: "week", key: "week"),
            Spec(suffix: "month", key: "month")
        ],
        .zai: [
            Spec(suffix: "session", key: "session"),
            Spec(suffix: "weekly", key: "weekly"),
            Spec(suffix: "webSearches", key: "webSearches")
        ]
    ]
}

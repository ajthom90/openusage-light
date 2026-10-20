import Foundation

enum DefaultLayout {
    static func expandingAccounts(_ metricIDs: [String], providerIDs: [String]) -> [String] {
        metricIDs.flatMap { metricID -> [String] in
            guard let separator = metricID.firstIndex(of: ".") else { return [metricID] }
            let family = String(metricID[..<separator])
            let suffix = metricID[separator...]
            let accountIDs = providerIDs.filter { $0.hasPrefix("\(family)@") }
            return [metricID] + accountIDs.map { "\($0)\(suffix)" }
        }
    }

    static let metricIDs: [String] = [
        "claude.session", "claude.weekly", "claude.sonnet", "claude.fable", "claude.extra",
        "codex.session", "codex.weekly", "codex.spark", "codex.sparkWeekly", "codex.credits",
        "cursor.usage", "cursor.auto", "cursor.api", "cursor.onDemand", "cursor.grokBot",
        "antigravity.geminiPro", "antigravity.geminiWeekly", "antigravity.argonWeekly",
        "antigravity.claude", "antigravity.claudeWeekly",
        "copilot.premium", "copilot.extra", "copilot.chat", "copilot.completions",
        "grok.weekly", "grok.payAsYouGo",
        "ollama.session", "ollama.weekly", "ollama.monthly", "ollama.purchasedCredits",
        "opencode.session", "opencode.weekly", "opencode.monthly",
        "openrouter.credits", "openrouter.balance", "openrouter.today", "openrouter.week",
        "openrouter.month", "openrouter.keyLimit",
        "zai.session", "zai.weekly", "zai.webSearches"
    ]

    static let migrationBaselineMetricIDs = metricIDs

    static let pinnedMetricIDs: [String] = [
        "claude.session", "claude.weekly",
        "codex.session", "codex.weekly",
        "cursor.auto", "cursor.api",
        "antigravity.geminiPro", "antigravity.geminiWeekly",
        "copilot.premium",
        "grok.weekly",
        "ollama.monthly",
        "opencode.session",
        "openrouter.credits",
        "zai.session", "zai.weekly"
    ]

    static let expandedMetricIDs: [String] = [
        "claude.sonnet", "claude.fable", "claude.extra",
        "codex.spark", "codex.sparkWeekly", "codex.credits",
        "cursor.onDemand", "cursor.grokBot",
        "antigravity.claude", "antigravity.claudeWeekly",
        "copilot.extra", "copilot.chat", "copilot.completions",
        "grok.payAsYouGo",
        "ollama.purchasedCredits",
        "opencode.monthly",
        "openrouter.balance", "openrouter.today", "openrouter.week", "openrouter.month", "openrouter.keyLimit",
        "zai.webSearches"
    ]
}

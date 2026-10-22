import Foundation

enum ProviderAuthMethod: Sendable, Equatable {
    case oauth
    case apiKey
}

enum ProviderKind: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case cursor
    case antigravity
    case copilot
    case grok
    case ollama
    case opencodeGo = "opencode"
    case openrouter
    case zai

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .antigravity: "Antigravity"
        case .copilot: "Copilot"
        case .grok: "Grok"
        case .ollama: "Ollama"
        case .opencodeGo: "OpenCode Go"
        case .openrouter: "OpenRouter"
        case .zai: "Z.ai"
        }
    }

    var iconSource: IconSource { .providerMark(rawValue) }

    /// The provider's quick links, revealed by clicking an account on the dashboard. The same links
    /// OpenUsage ships.
    var links: [ProviderLink] {
        switch self {
        case .claude: [.init(label: "Status", url: "https://status.anthropic.com/"),
                       .init(label: "Dashboard", url: "https://claude.ai/settings/usage")]
        case .codex: [.init(label: "Status", url: "https://status.openai.com/"),
                      .init(label: "Dashboard", url: "https://chatgpt.com/settings/usage")]
        case .cursor: [.init(label: "Status", url: "https://status.cursor.com/"),
                       .init(label: "Dashboard", url: "https://www.cursor.com/dashboard")]
        case .antigravity: []
        case .copilot: [.init(label: "Status", url: "https://www.githubstatus.com/"),
                        .init(label: "Dashboard", url: "https://github.com/settings/billing")]
        case .grok: [.init(label: "Usage", url: "https://grok.com/?_s=usage")]
        case .ollama: [.init(label: "Usage", url: "https://ollama.com/settings"),
                       .init(label: "API Keys", url: "https://ollama.com/settings/keys")]
        case .opencodeGo: [.init(label: "Dashboard", url: "https://opencode.ai/auth")]
        case .openrouter: [.init(label: "Activity", url: "https://openrouter.ai/activity"),
                           .init(label: "Credits", url: "https://openrouter.ai/settings/credits")]
        case .zai: [.init(label: "Dashboard", url: "https://z.ai/manage-apikey/coding-plan/personal/my-plan"),
                    .init(label: "API Keys", url: "https://z.ai/manage-apikey/apikey-list")]
        }
    }

    var authMethod: ProviderAuthMethod {
        switch self {
        case .claude, .codex, .cursor, .antigravity, .copilot, .grok: .oauth
        case .ollama, .opencodeGo, .openrouter, .zai: .apiKey
        }
    }
}

struct Account: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: ProviderKind
    var label: String
    let addedAt: Date

    var cardID: String {
        "\(kind.rawValue)@\(id.uuidString.lowercased().prefix(8))"
    }

    init(id: UUID = UUID(), kind: ProviderKind, label: String, addedAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.label = label
        self.addedAt = addedAt
    }
}

struct OAuthTokens: Codable, Sendable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var extras: [String: String]

    init(accessToken: String, refreshToken: String? = nil, expiresAt: Date? = nil, extras: [String: String] = [:]) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.extras = extras
    }
}

enum AccountCredential: Codable, Sendable, Equatable {
    case oauth(OAuthTokens)
    case apiKey(String)
}

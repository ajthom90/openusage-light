import Foundation
import OpenUsageCore

/// The Mac app's sign-ins: the browser ones that need its loopback listener, then the shared ones.
enum ProviderLoginCatalog {
    static func login(for kind: ProviderKind) -> any ProviderLogin {
        switch kind {
        case .claude: ClaudeLogin()
        case .codex: CodexLogin()
        case .antigravity: AntigravityLogin()
        case .cursor, .copilot, .grok, .musecode, .ollama, .opencodeGo, .openrouter, .zai:
            SharedProviderLogins.login(for: kind)!
        }
    }
}

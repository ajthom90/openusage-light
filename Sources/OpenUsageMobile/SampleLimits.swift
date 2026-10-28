import Foundation
import OpenUsageCore

/// A small limits document for previews and for a build with no iCloud container.
enum SampleLimits {
    /// Times are relative to `now`, so the example always looks freshly fetched.
    static func json(now: Date = Date()) -> String {
        func at(_ seconds: TimeInterval) -> String { OpenUsageISO8601.string(from: now.addingTimeInterval(seconds)) }
        return """
    {
      "schema": "openusage.limits.v1",
      "generatedAt": "\(at(0))",
      "order": ["claude@sample1", "codex@sample2", "openrouter@sample3"],
      "errors": [],
      "providers": {
        "claude@sample1": {
          "provider": "claude", "displayName": "Claude", "account": "Work", "plan": "Max 20x",
          "fetchedAt": "\(at(-60))", "expiresAt": "\(at(240))", "stale": false,
          "resources": {
            "session": {"kind": "consumption", "unit": "percent", "used": 36, "limit": 100, "remaining": 64, "utilization": 0.36, "resetsAt": "\(at(10_000))", "windowSeconds": 18000},
            "weekly": {"kind": "consumption", "unit": "percent", "used": 68, "limit": 100, "remaining": 32, "utilization": 0.68, "resetsAt": "\(at(300_000))", "windowSeconds": 604800}
          }
        },
        "codex@sample2": {
          "provider": "codex", "displayName": "Codex", "account": "Personal", "plan": "Pro 100",
          "fetchedAt": "\(at(-60))", "expiresAt": "\(at(240))", "stale": false,
          "resources": {
            "session": {"kind": "consumption", "unit": "percent", "used": 94, "limit": 100, "remaining": 6, "utilization": 0.94, "resetsAt": "\(at(4_000))", "windowSeconds": 18000}
          }
        },
        "openrouter@sample3": {
          "provider": "openrouter", "displayName": "OpenRouter", "account": "OpenRouter", "plan": "Free",
          "fetchedAt": "\(at(-60))", "expiresAt": "\(at(240))", "stale": false,
          "resources": {
            "balance": {"kind": "balance", "unit": "usd", "available": 12.4}
          }
        }
      }
    }
    """
    }
}

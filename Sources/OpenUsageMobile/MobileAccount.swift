import Foundation
import OpenUsageCore

/// One meter on a phone card, ready to draw.
public struct MobileMeter: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    /// 0...1 for a bounded meter; `nil` for a balance or an unbounded count.
    public let fraction: Double?
    public let valueText: String
    public let resetsAt: Date?
}

/// One account card: what the dashboard shows for it, built from the limits document.
public struct MobileAccount: Identifiable, Equatable, Sendable {
    public let id: String
    public let providerName: String
    public let name: String
    public let plan: String?
    public let fetchedAt: Date
    public let isStale: Bool
    public let meters: [MobileMeter]

    /// The accounts in the document's order, which is the order the user saved on the Mac.
    package static func accounts(in envelope: LimitsEnvelope) -> [MobileAccount] {
        envelope.order.compactMap { id in
            guard let provider = envelope.providers[id] else { return nil }
            let meters = provider.resources.keys.sorted().compactMap { key in
                provider.resources[key].map { meter(key: key, $0) }
            }
            return MobileAccount(
                id: id, providerName: provider.displayName, name: provider.account, plan: provider.plan,
                fetchedAt: provider.fetchedAt, isStale: provider.stale, meters: meters
            )
        }
    }

    private static func meter(key: String, _ resource: LimitsEnvelope.Resource) -> MobileMeter {
        MobileMeter(
            id: key, title: title(for: key), fraction: resource.utilization.map { min(max($0, 0), 1) },
            valueText: valueText(resource), resetsAt: resource.resetsAt
        )
    }

    /// `rateLimitResets` → "Rate Limit Resets"; `session` → "Session".
    static func title(for key: String) -> String {
        var words = ""
        for character in key {
            if character.isUppercase, !words.isEmpty { words.append(" ") }
            words.append(character)
        }
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    static func valueText(_ resource: LimitsEnvelope.Resource) -> String {
        switch resource.kind {
        case .consumption:
            guard let used = resource.used else { return "" }
            if resource.unit == "percent" { return "\(number(used))% used" }
            if let limit = resource.limit { return "\(amount(used, resource.unit)) of \(amount(limit, resource.unit))" }
            return amount(used, resource.unit)
        case .balance:
            return resource.available.map { "\(amount($0, resource.unit)) available" } ?? ""
        }
    }

    private static func amount(_ value: Double, _ unit: String) -> String {
        unit == "usd" ? "$" + String(format: "%.2f", value) : "\(number(value)) \(unit)"
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

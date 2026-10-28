import Foundation
import OpenUsageCore

/// One meter on a phone card, ready to draw.
public struct MobileMeter: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    /// 0...1 for a bounded meter, as the bar fills: what is used or what is left, per the display setting.
    /// `nil` for a balance or an unbounded count.
    public let fraction: Double?
    /// How much is used, 0...1, whatever the display setting: what colours the bar and picks the closest meter.
    public let usedFraction: Double?
    public let valueText: String
    /// The same reading, short enough for a small widget: "36%" or "64% left", "$12.40".
    public let shortText: String
    public let resetsAt: Date?
}

/// One account card: what the dashboard shows for it, built from the limits document.
public struct MobileAccount: Identifiable, Equatable, Sendable {
    public let id: String
    public let providerName: String
    /// The name the user gave the account, or empty when it is only an email address (which is never shown).
    public let name: String
    public let plan: String?
    public let fetchedAt: Date
    public let isStale: Bool
    public let meters: [MobileMeter]

    /// The meter that stands for the account on a small widget: its first bounded meter (the session, for a
    /// provider that has one), or else its first meter.
    public var headline: MobileMeter? {
        meters.first { $0.fraction != nil } ?? meters.first
    }

    /// The accounts in the document's order, which is the order the user saved on the Mac.
    package static func accounts(in envelope: LimitsEnvelope, display: UsageDisplay = .used) -> [MobileAccount] {
        envelope.order.compactMap { id in
            guard let provider = envelope.providers[id] else { return nil }
            // The dashboard's row order, then anything the document names that this version does not know.
            let known = ProviderKind(rawValue: provider.provider).map(LimitsProjection.resourceKeys(for:)) ?? []
            let keys = known.filter { provider.resources[$0] != nil } + provider.resources.keys.filter { !known.contains($0) }.sorted()
            let meters = keys.compactMap { key in provider.resources[key].map { meter(key: key, $0, display) } }
            return MobileAccount(
                id: id, providerName: provider.displayName, name: provider.account.contains("@") ? "" : provider.account, plan: provider.plan,
                fetchedAt: provider.fetchedAt, isStale: provider.stale, meters: meters
            )
        }
    }

    private static func meter(key: String, _ resource: LimitsEnvelope.Resource, _ display: UsageDisplay) -> MobileMeter {
        let used = resource.utilization.map { min(max($0, 0), 1) }
        let fraction = used.map { display == .remaining ? 1 - $0 : $0 }
        return MobileMeter(
            id: key, title: title(for: key), fraction: fraction, usedFraction: used,
            valueText: valueText(resource, display), shortText: shortText(resource, display, fraction: fraction),
            resetsAt: resource.resetsAt
        )
    }

    /// `rateLimitResets` → "Rate Limit Resets"; `session` → "Session"; `apiUsage` → "API Usage".
    static func title(for key: String) -> String {
        var words: [String] = [""]
        for character in key {
            if character.isUppercase, !(words.last ?? "").isEmpty { words.append("") }
            words[words.count - 1].append(character)
        }
        let acronyms: Set<String> = ["api", "usd"]
        return words.map { acronyms.contains($0.lowercased()) ? $0.uppercased() : $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    static func valueText(_ resource: LimitsEnvelope.Resource, _ display: UsageDisplay) -> String {
        switch resource.kind {
        case .consumption:
            guard let used = resource.used else { return "" }
            let left = resource.remaining ?? resource.limit.map { max($0 - used, 0) }
            if resource.unit == "percent" {
                return display == .remaining ? "\(number(left ?? max(100 - used, 0)))% left" : "\(number(used))% used"
            }
            if display == .remaining, let left { return "\(amount(left, resource.unit)) left" }
            if let limit = resource.limit { return "\(amount(used, resource.unit)) of \(amount(limit, resource.unit))" }
            return amount(used, resource.unit)
        case .balance:
            return resource.available.map { "\(amount($0, resource.unit)) available" } ?? ""
        }
    }

    /// "36%" (used) or "64% left"; a balance or count without its trailing word.
    static func shortText(_ resource: LimitsEnvelope.Resource, _ display: UsageDisplay, fraction: Double?) -> String {
        if let fraction { return "\(Int((fraction * 100).rounded()))%" + (display == .remaining ? " left" : "") }
        return valueText(resource, display).replacingOccurrences(of: " available", with: "")
    }

    private static func amount(_ value: Double, _ unit: String) -> String {
        unit == "usd" ? "$" + String(format: "%.2f", value) : "\(number(value)) \(unit)"
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

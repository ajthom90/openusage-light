import Foundation

/// The dashboard's shape: one card per provider (Claude, Codex, …) holding that provider's accounts in
/// the user's account order. Built from `LayoutStore.displayGroups`, which has one group per account.
/// Only readings that carry data become lines, and the Rate Limit Resets reading only while at least one
/// reset is available.
struct DashboardFamily: Identifiable {
    let id: String
    /// The first account's provider, which supplies the card's mark and name.
    let provider: Provider
    var accounts: [DashboardAccount]
}

struct DashboardAccount: Identifiable {
    let provider: Provider
    /// One line per enabled metric that has data.
    let lines: [DashboardLine]

    var id: String { provider.id }
    var name: String { provider.accountLabel ?? provider.displayName }
}

struct DashboardLine: Identifiable {
    let descriptor: WidgetDescriptor
    let data: WidgetData
    var id: String { descriptor.id }
}

extension DashboardFamily {
    /// "claude" for the account card "claude@8ad3b217".
    static func familyID(of providerID: String) -> String {
        String(providerID.split(separator: "@", maxSplits: 1).first ?? Substring(providerID))
    }

    /// Groups accounts under their provider in order of first appearance. Every enabled metric that
    /// has data is a line; nothing is tucked behind a click.
    static func make(groups: [ProviderGroup], line: (PlacedWidget) -> DashboardLine?) -> [DashboardFamily] {
        var families: [DashboardFamily] = []
        for group in groups {
            let account = DashboardAccount(provider: group.provider, lines: group.widgets.compactMap(line).filter(\.isShown))
            let familyID = familyID(of: group.provider.id)
            if let index = families.firstIndex(where: { $0.id == familyID }) {
                families[index].accounts.append(account)
            } else {
                families.append(DashboardFamily(id: familyID, provider: group.provider, accounts: [account]))
            }
        }
        return families
    }
}

private extension DashboardLine {
    var isShown: Bool { data.hasData && (!data.showsResetExpiries || data.resetCreditCount > 0) }
}

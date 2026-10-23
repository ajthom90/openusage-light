import Foundation

/// The dashboard's shape: one card per provider (Claude, Codex, …) holding that provider's accounts in
/// the user's account order. Built from `LayoutStore.displayGroups`, which has one group per account.
/// Every enabled reading that carries data becomes a line, except the Rate Limit Resets reading: while a
/// reset is available it rides on the account line as the ↺ tag instead.
struct DashboardFamily: Identifiable {
    let id: String
    /// The first account's provider, which supplies the card's mark and name.
    let provider: Provider
    var accounts: [DashboardAccount]

    /// The card's account when it has exactly one. Its header then stands in for the account's name line.
    var soleAccount: DashboardAccount? { accounts.count == 1 ? accounts[0] : nil }
}

struct DashboardAccount: Identifiable {
    let provider: Provider
    /// One line per enabled metric that has data, in the user's order.
    let lines: [DashboardLine]
    /// The Rate Limit Resets reading, present only while at least one reset is available.
    var resets: WidgetData?

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
            let all = group.widgets.compactMap(line)
            let resets = all.first { $0.data.showsResetExpiries }?.data
            let account = DashboardAccount(
                provider: group.provider,
                lines: all.filter { $0.data.hasData && !$0.data.showsResetExpiries },
                resets: resets.flatMap { $0.hasData && $0.resetCreditCount > 0 ? $0 : nil }
            )
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

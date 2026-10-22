import Foundation

/// The dashboard's shape: one card per provider (Claude, Codex, …) holding that provider's accounts in
/// the user's account order. Built from `LayoutStore.displayGroups`, which has one group per account.
/// Only readings that carry data become lines. An account's Rate Limit Resets reading never becomes a
/// line: when resets are available it rides on the account line as the reset count instead.
struct DashboardFamily: Identifiable {
    let id: String
    /// The first account's provider, which supplies the card's mark and name.
    let provider: Provider
    var accounts: [DashboardAccount]
}

struct DashboardAccount: Identifiable {
    let provider: Provider
    /// Always-visible lines.
    let lines: [DashboardLine]
    /// Lines revealed by clicking the account.
    let extraLines: [DashboardLine]
    /// The Rate Limit Resets reading, present only while at least one reset is available.
    let resets: WidgetData?

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

    /// Groups accounts under their provider in order of first appearance. When none of an account's
    /// always-visible lines has data, its extra lines take their place, so an account never shows an
    /// empty block with something hidden behind a click.
    static func make(groups: [ProviderGroup], line: (PlacedWidget) -> DashboardLine?) -> [DashboardFamily] {
        var families: [DashboardFamily] = []
        for group in groups {
            let always = group.alwaysShownWidgets.compactMap(line)
            let extra = group.expandedWidgets.compactMap(line)
            let resets = (always + extra).first { $0.data.showsResetExpiries }?.data
            let shownAlways = always.filter(\.isShown)
            let shownExtra = extra.filter(\.isShown)
            let account = DashboardAccount(
                provider: group.provider,
                lines: shownAlways.isEmpty ? shownExtra : shownAlways,
                extraLines: shownAlways.isEmpty ? [] : shownExtra,
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

private extension DashboardLine {
    var isShown: Bool { data.hasData && !data.showsResetExpiries }
}

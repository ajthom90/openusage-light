import Foundation

/// The dashboard's shape: one card per provider (Claude, Codex, …) holding that provider's accounts in
/// the user's account order. Built from `LayoutStore.displayGroups`, which has one group per account.
/// Every enabled reading that carries data becomes a line; the Limit Resets reading only while a reset
/// is available.
struct DashboardFamily: Identifiable {
    let id: String
    /// The first account's provider, which supplies the card's mark and name.
    let provider: Provider
    var accounts: [DashboardAccount]

    /// The card's account when it has exactly one. Its header then names the account.
    var soleAccount: DashboardAccount? { accounts.count == 1 ? accounts[0] : nil }

    /// The sole account when it has a name of its own, which the header reads as "Provider — name"
    /// when that fits its line (`DashboardProviderSection`). An account named like its provider, or
    /// one of several, leaves the header to the provider alone.
    var namedSoleAccount: DashboardAccount? {
        guard let account = soleAccount, account.name != provider.displayName else { return nil }
        return account
    }

    /// The same family with every email address left out of its account names, for an image that
    /// leaves the panel: an account named by its email reads as its provider alone.
    var hidingEmails: DashboardFamily {
        DashboardFamily(
            id: id, provider: provider.hidingEmail,
            accounts: accounts.map { DashboardAccount(provider: $0.provider.hidingEmail, lines: $0.lines) }
        )
    }
}

struct DashboardAccount: Identifiable {
    let provider: Provider
    /// One line per enabled metric that has data, in the user's order.
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
            let lines = group.widgets.compactMap(line).filter {
                $0.data.hasData && (!$0.data.showsResetExpiries || $0.data.resetCreditCount > 0)
            }
            let account = DashboardAccount(provider: group.provider, lines: lines)
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

extension Provider {
    /// Whether the account is named by an email address rather than a name of its own.
    var isNamedByEmail: Bool {
        accountLabel?.contains("@") ?? false
    }

    /// The provider with an email account name left out.
    var hidingEmail: Provider {
        guard isNamedByEmail else { return self }
        return Provider(id: id, displayName: displayName, icon: icon, accountLabel: nil, links: links)
    }
}

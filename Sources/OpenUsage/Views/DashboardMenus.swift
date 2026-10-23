import SwiftUI

/// What a dashboard right-click menu item does. `WidgetGroupedListView` performs it.
enum DashboardCommand: Equatable {
    case refresh([String])
    case manageAccounts
    case open(URL)
    case rename(String)
    case editAccount(String)
    case shareScreenshot(String)
    case showHiddenMetrics(String)
    case toggleStar(String)
    case hide(String)
}

struct DashboardMenuItem: Equatable {
    let title: String
    /// `nil` shows the title as a disabled line.
    var command: DashboardCommand?
}

/// The dashboard's right-click menus, one per thing you can click: a provider's card, an account, and a
/// metric line. A card with one account has no account line, so its card menu merges the two
/// (`soleAccount`). Each is a list of sections that render with dividers between them. Apart from the ↺
/// tag's resets popover, right-click is the only way to act on the dashboard.
enum DashboardMenus {
    typealias Sections = [[DashboardMenuItem]]

    static func provider(_ family: DashboardFamily) -> Sections {
        [
            [DashboardMenuItem(title: "Refresh", command: .refresh(family.accounts.map(\.id)))],
            [DashboardMenuItem(title: "Manage Accounts…", command: .manageAccounts)],
            links(family.provider),
        ].filter { !$0.isEmpty }
    }

    /// The card menu of a provider with one account: the status line, then Refresh, then the commands
    /// that edit the account and its provider's accounts, sharing, the view option, and the provider's
    /// web pages last.
    static func soleAccount(
        _ account: DashboardAccount,
        status: String?,
        canShare: Bool,
        hasHiddenMetrics: Bool
    ) -> Sections {
        [
            status.map { [DashboardMenuItem(title: $0)] } ?? [],
            [DashboardMenuItem(title: "Refresh", command: .refresh([account.id]))],
            [
                DashboardMenuItem(title: "Rename", command: .rename(account.id)),
                DashboardMenuItem(title: "Edit Account…", command: .editAccount(account.id)),
                DashboardMenuItem(title: "Manage Accounts…", command: .manageAccounts),
            ],
            canShare ? [DashboardMenuItem(title: "Share Screenshot", command: .shareScreenshot(account.id))] : [],
            hasHiddenMetrics ? [DashboardMenuItem(title: "Show Hidden Metrics", command: .showHiddenMetrics(account.id))] : [],
            links(account.provider),
        ].filter { !$0.isEmpty }
    }

    private static func links(_ provider: Provider) -> [DashboardMenuItem] {
        provider.visibleLinks.compactMap { link in
            URL(string: link.url).map { DashboardMenuItem(title: link.label, command: .open($0)) }
        }
    }

    /// `status` explains the account line's warning or stale icon.
    static func account(
        _ account: DashboardAccount,
        status: String?,
        canShare: Bool,
        hasHiddenMetrics: Bool
    ) -> Sections {
        [
            status.map { [DashboardMenuItem(title: $0)] } ?? [],
            [
                DashboardMenuItem(title: "Refresh", command: .refresh([account.id])),
                DashboardMenuItem(title: "Rename", command: .rename(account.id)),
                DashboardMenuItem(title: "Edit Account…", command: .editAccount(account.id)),
            ],
            canShare ? [DashboardMenuItem(title: "Share Screenshot", command: .shareScreenshot(account.id))] : [],
            hasHiddenMetrics ? [DashboardMenuItem(title: "Show Hidden Metrics", command: .showHiddenMetrics(account.id))] : [],
        ].filter { !$0.isEmpty }
    }

    static func metric(_ descriptor: WidgetDescriptor, isStarred: Bool) -> Sections {
        var items: [DashboardMenuItem] = []
        if descriptor.pinnable {
            items.append(DashboardMenuItem(title: isStarred ? "Unstar" : "Star for Menu Bar", command: .toggleStar(descriptor.id)))
        }
        items.append(DashboardMenuItem(title: "Hide", command: .hide(descriptor.id)))
        return [items]
    }
}

/// Renders a `DashboardMenus` list inside `.contextMenu`.
struct DashboardMenu: View {
    let sections: DashboardMenus.Sections
    let perform: (DashboardCommand) -> Void

    var body: some View {
        ForEach(sections.indices, id: \.self) { index in
            if index > 0 { Divider() }
            ForEach(sections[index].indices, id: \.self) { item in
                let entry = sections[index][item]
                Button(entry.title) {
                    if let command = entry.command { perform(command) }
                }
                .disabled(entry.command == nil)
            }
        }
    }
}

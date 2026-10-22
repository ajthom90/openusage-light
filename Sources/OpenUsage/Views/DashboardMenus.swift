import SwiftUI

/// What a dashboard right-click menu item does. `WidgetGroupedListView` performs it.
enum DashboardCommand: Equatable {
    case refresh([String])
    case manageAccounts
    case open(URL)
    case rename(String)
    case editAccount(String)
    case shareScreenshot(String)
    case useReset(accountID: String, expiry: Date)
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
/// metric line. Each is a list of sections that render with dividers between them. Right-click is the
/// only way to act on the dashboard, so anything a click or hover used to reveal lives here.
enum DashboardMenus {
    typealias Sections = [[DashboardMenuItem]]

    static func provider(_ family: DashboardFamily) -> Sections {
        let links = family.provider.visibleLinks.compactMap { link in
            URL(string: link.url).map { DashboardMenuItem(title: link.label, command: .open($0)) }
        }
        return [
            [DashboardMenuItem(title: "Refresh", command: .refresh(family.accounts.map(\.id)))],
            [DashboardMenuItem(title: "Manage Accounts…", command: .manageAccounts)],
            links,
        ].filter { !$0.isEmpty }
    }

    /// `status` explains the account line's warning or stale icon. `canClaimReset` is whether the
    /// provider takes a claim for this account right now.
    static func account(
        _ account: DashboardAccount,
        status: String?,
        canShare: Bool,
        canClaimReset: Bool,
        hasHiddenMetrics: Bool,
        now: Date = Date()
    ) -> Sections {
        var reset: [DashboardMenuItem] = []
        if let resets = account.resets {
            let soonest = resets.expiriesAt.filter { $0 > now }.min()
            reset.append(DashboardMenuItem(
                title: soonest.map { "Use a Reset (Expires \(expiryDate($0, now: now)))…" } ?? "Use a Reset…",
                command: soonest.flatMap { canClaimReset ? .useReset(accountID: account.id, expiry: $0) : nil }
            ))
        }
        if hasHiddenMetrics {
            reset.append(DashboardMenuItem(title: "Show Hidden Metrics", command: .showHiddenMetrics(account.id)))
        }
        return [
            status.map { [DashboardMenuItem(title: $0)] } ?? [],
            [
                DashboardMenuItem(title: "Refresh", command: .refresh([account.id])),
                DashboardMenuItem(title: "Rename", command: .rename(account.id)),
                DashboardMenuItem(title: "Edit Account…", command: .editAccount(account.id)),
            ],
            canShare ? [DashboardMenuItem(title: "Share Screenshot", command: .shareScreenshot(account.id))] : [],
            reset,
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

    /// "Oct 28", with the year only when it isn't this year's.
    static func expiryDate(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        let style = calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? Date.FormatStyle.dateTime.month(.abbreviated).day()
            : Date.FormatStyle.dateTime.month(.abbreviated).day().year()
        return date.formatted(style)
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

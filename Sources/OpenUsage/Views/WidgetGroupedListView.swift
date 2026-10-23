import AppKit
import SwiftUI

/// The dashboard display: one card per provider, holding each of its accounts (`DashboardFamily`).
/// Every account shows its plan and reset tags and every metric that has data, fed by the same
/// `WidgetDataStore` the menu bar uses. A card with one account shows them in its header and has no
/// account name line. The ↺ tag is the one thing that reacts to hover or a click: it opens the account's
/// resets timeline, where a reset is claimed. A double-click on an account's name renames it, the same
/// as the menu's Rename.
///
/// Right-click a provider's card, an account, or a metric line for its menu (`DashboardMenus`); a
/// one-account card's menu holds the account's commands too. Everything reorders by dragging: a card by
/// its header, an account by its name line within its card, a metric line within its account.
struct WidgetGroupedListView: View {
    @Environment(AppContainer.self) private var container
    @Environment(LayoutStore.self) private var layout
    @Environment(WidgetDataStore.self) private var dataStore
    @Environment(AccountRenameStore.self) private var renaming
    @Environment(\.colorScheme) private var colorScheme
    let reorderSpaceName: String
    @Binding var reorderLift: ReorderLift?

    @State private var frameStore = ReorderFrameStore()
    @State private var activeMetricID: String?
    @State private var activeAccountID: String?
    @State private var activeFamilyID: String?

    var body: some View {
        let groups = layout.displayGroups
        let families = DashboardFamily.make(groups: groups, line: resolveLine)
        VStack(alignment: .leading, spacing: DashboardBox.cardSpacing) {
            ForEach(families) { family in
                DashboardProviderCard(
                    family: family,
                    badges: badges,
                    handle: { AnyView($0.highPriorityGesture(familyDragGesture(for: family))) }
                ) { account in
                    accountSection(account, in: family)
                }
                .contextMenu { DashboardMenu(sections: cardMenu(family), perform: perform) }
                .opacity(activeFamilyID == Self.familyFrameID(family.id) ? 0 : 1)
                .reorderFrame(id: Self.familyFrameID(family.id), in: .named(reorderSpaceName))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onPreferenceChange(ReorderFramePreferenceKey.self) { frameStore.frames = $0 }
        .animation(Motion.spring, value: families.map(\.id))
    }

    private func resolveLine(_ widget: PlacedWidget) -> DashboardLine? {
        guard let descriptor = layout.descriptor(for: widget) else { return nil }
        return DashboardLine(descriptor: descriptor, data: dataStore.data(for: descriptor))
    }

    /// The account's visible line ids, read live so a drag sees each reorder it has already made.
    private func visibleLineIDs(for accountID: String) -> [String] {
        let groups = layout.displayGroups.filter { $0.provider.id == accountID }
        guard let account = DashboardFamily.make(groups: groups, line: resolveLine).first?.accounts.first else {
            return []
        }
        return account.lines.map(\.id)
    }

    /// Metrics the user hid from this account that have something to show.
    private func hiddenMetricIDs(for accountID: String) -> [String] {
        layout.orderedSupportedMetrics(for: accountID)
            .filter { !layout.isMetricEnabled($0.id) && dataStore.data(for: $0).hasData }
            .map(\.id)
    }

    /// A one-account card's menu merges the account's commands into the provider's.
    private func cardMenu(_ family: DashboardFamily) -> DashboardMenus.Sections {
        guard let account = family.soleAccount else { return DashboardMenus.provider(family) }
        return DashboardMenus.soleAccount(
            account,
            status: statusReason(for: account.id),
            canShare: canShare(account.id),
            hasHiddenMetrics: !hiddenMetricIDs(for: account.id).isEmpty
        )
    }

    /// Why the account shows a warning or stale icon.
    private func statusReason(for accountID: String) -> String? {
        dataStore.headerNotice(for: accountID) ?? dataStore.stalenessHint(for: accountID)?.tooltip
    }

    private func canShare(_ accountID: String) -> Bool {
        layout.displayGroups.contains { $0.provider.id == accountID }
    }

    private func badges(for account: DashboardAccount) -> AccountBadges {
        AccountBadges(
            resets: account.resets,
            plan: dataStore.plan(for: account.id),
            notice: dataStore.headerNotice(for: account.id),
            refreshing: dataStore.refreshingProviderIDs.contains(account.id),
            staleness: dataStore.stalenessHint(for: account.id),
            resetClaim: container.resetClaim(for: account.id)
        )
    }

    /// An account with its menu and drag. On a one-account card it is only its metric lines: the card's
    /// header and menu stand in for its name line and menu, and there is no other account to reorder.
    @ViewBuilder
    private func accountSection(_ account: DashboardAccount, in family: DashboardFamily) -> some View {
        if family.soleAccount != nil {
            plainAccountSection(account, in: family) { metricLine($0, in: account) }
        } else {
            plainAccountSection(
                account,
                in: family,
                handle: { AnyView($0.highPriorityGesture(accountDragGesture(for: account, in: family))) }
            ) { line in
                metricLine(line, in: account)
            }
            .contextMenu {
                DashboardMenu(
                    sections: DashboardMenus.account(
                        account,
                        status: statusReason(for: account.id),
                        canShare: canShare(account.id),
                        hasHiddenMetrics: !hiddenMetricIDs(for: account.id).isEmpty
                    ),
                    perform: perform
                )
            }
            .opacity(activeAccountID == account.id ? 0 : 1)
            .reorderFrame(id: account.id, in: .named(reorderSpaceName))
        }
    }

    private func plainAccountSection<Line: View>(
        _ account: DashboardAccount,
        in family: DashboardFamily,
        handle: @escaping (AnyView) -> AnyView = { $0 },
        @ViewBuilder line: @escaping (DashboardLine) -> Line
    ) -> some View {
        DashboardAccountSection(
            account: account,
            badges: badges(for: account),
            showsAccountLine: family.soleAccount == nil,
            handle: handle,
            line: line
        )
    }

    /// A metric line with its right-click menu. It drags to reorder within its account.
    private func metricLine(_ line: DashboardLine, in account: DashboardAccount) -> some View {
        DashboardMetricLine(data: line.data)
            .contentShape(Rectangle())
            .opacity(activeMetricID == line.id ? 0 : 1)
            .highPriorityGesture(metricDragGesture(for: line, accountID: account.id))
            .contextMenu {
                DashboardMenu(
                    sections: DashboardMenus.metric(line.descriptor, isStarred: layout.isPinned(line.descriptor.id)),
                    perform: perform
                )
            }
            .reorderFrame(id: line.id, in: .named(reorderSpaceName))
    }

    // MARK: - Menu commands

    private func perform(_ command: DashboardCommand) {
        switch command {
        case .refresh(let accountIDs):
            Task {
                for id in accountIDs { await dataStore.refreshOnUserRequest(providerID: id) }
            }
        case .manageAccounts:
            openAccounts(nil)
        case .open(let url):
            NSWorkspace.shared.open(url)
        case .rename(let accountID):
            renaming.begin(accountID)
        case .editAccount(let accountID):
            openAccounts(accountID)
        case .shareScreenshot(let accountID):
            guard let group = layout.displayGroups.first(where: { $0.provider.id == accountID }) else { return }
            _ = ShareCardRenderer.share(group: group, dataStore: dataStore, layout: layout, appearance: colorScheme)
        case .showHiddenMetrics(let accountID):
            layout.showMetrics(hiddenMetricIDs(for: accountID))
        case .toggleStar(let descriptorID):
            if layout.isPinned(descriptorID) || layout.canPin(descriptorID) {
                layout.togglePin(descriptorID)
            } else {
                layout.notePinDenied(descriptorID)
            }
        case .hide(let descriptorID):
            layout.setMetricEnabled(descriptorID, false)
        }
    }

    /// Opens the Accounts screen, on one account's page when `providerID` is set.
    private func openAccounts(_ providerID: String?) {
        withAnimation(Motion.modeSwitch) {
            layout.customizeProviderID = providerID
            layout.isEditing = true
        }
    }

    // MARK: - Reordering

    private func metricDragGesture(for line: DashboardLine, accountID: String) -> some Gesture {
        reorderDragGesture(
            id: line.id,
            coordinateSpaceName: reorderSpaceName,
            frameStore: frameStore,
            active: $activeMetricID,
            lift: $reorderLift,
            makeLift: { value in
                let preview = DashboardMetricLine(data: line.data)
                    .padding(.horizontal, 4)
                    .liftedRowSurface()
                return ReorderLift.make(id: line.id, payload: .view(AnyView(preview)), value: value, frames: frameStore.frames)
            },
            orderedIDs: { visibleLineIDs(for: accountID) },
            reorder: { layout.reorderMetric(dragged: line.id, target: $0, in: accountID) }
        )
    }

    private static func familyFrameID(_ familyID: String) -> String { "family:\(familyID)" }

    private func liveFamilies() -> [DashboardFamily] {
        DashboardFamily.make(groups: layout.displayGroups, line: resolveLine)
    }

    private func accountDragGesture(for account: DashboardAccount, in family: DashboardFamily) -> some Gesture {
        reorderDragGesture(
            id: account.id,
            coordinateSpaceName: reorderSpaceName,
            frameStore: frameStore,
            active: $activeAccountID,
            lift: $reorderLift,
            makeLift: { value in
                let preview = plainAccountSection(account, in: family) { DashboardMetricLine(data: $0.data) }
                    .liftedRowSurface()
                return ReorderLift.make(id: account.id, payload: .view(AnyView(preview)), value: value, frames: frameStore.frames)
            },
            orderedIDs: { liveFamilies().first { $0.id == family.id }?.accounts.map(\.id) ?? [] },
            reorder: { layout.reorderProvider(dragged: account.id, target: $0) }
        )
    }

    private func familyDragGesture(for family: DashboardFamily) -> some Gesture {
        let frameID = Self.familyFrameID(family.id)
        return reorderDragGesture(
            id: frameID,
            coordinateSpaceName: reorderSpaceName,
            frameStore: frameStore,
            active: $activeFamilyID,
            lift: $reorderLift,
            makeLift: { value in
                let preview = DashboardProviderCard(family: family, badges: badges) {
                    plainAccountSection($0, in: family) { DashboardMetricLine(data: $0.data) }
                }
                return ReorderLift.make(id: frameID, payload: .view(AnyView(preview)), value: value, frames: frameStore.frames)
            },
            orderedIDs: { liveFamilies().map { Self.familyFrameID($0.id) } },
            reorder: { target in
                layout.reorderFamily(dragged: family.id, target: String(target.dropFirst("family:".count)))
            }
        )
    }
}

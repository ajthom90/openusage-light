import AppKit
import SwiftUI

/// The dashboard display: one provider after another (`DashboardFamily`), each a header above a card
/// of its accounts, every account one row per metric that has data, fed by the same `WidgetDataStore`
/// the menu bar uses. Every row shows its label, bar, value and reset at rest and reacts to nothing but
/// a dwell: its account's resets open below it after a moment. While the pointer is anywhere on a
/// provider its logo turns into the copy button. A double-click on an
/// account's name, in the header or on its caption, renames it, the same as the menu's Rename.
///
/// Right-click a provider's header or card, an account, or a metric row for its menu (`DashboardMenus`);
/// a one-account provider's menu holds the account's commands too. Everything reorders by dragging: a
/// provider by its header, an account by its caption within its card, a metric row within its account.
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
    /// The provider under the pointer, whose logo is the copy button.
    @State private var hoveredFamilyID: String?

    var body: some View {
        let families = liveFamilies()
        VStack(alignment: .leading, spacing: DashboardGrid.sectionSpacing) {
            ForEach(families) { family in
                section(family)
                    .contextMenu { DashboardMenu(sections: familyMenu(family), perform: perform) }
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

    private func liveFamilies() -> [DashboardFamily] {
        DashboardFamily.make(groups: layout.displayGroups, line: resolveLine)
    }

    private func plans(for family: DashboardFamily) -> [String: String] {
        Dictionary(uniqueKeysWithValues: family.accounts.compactMap { account in
            dataStore.plan(for: account.id).map { (account.id, $0) }
        })
    }

    private func status(for accountID: String) -> AccountStatus {
        AccountStatus(
            refreshing: dataStore.refreshingProviderIDs.contains(accountID),
            notice: dataStore.headerNotice(for: accountID),
            staleness: dataStore.stalenessHint(for: accountID)
        )
    }

    // MARK: - Sections

    /// A provider with its hover: while the pointer is on its header or card, the logo is the copy button.
    private func section(_ family: DashboardFamily) -> some View {
        let plans = plans(for: family)
        return DashboardProviderSection(
            family: family,
            plans: plans,
            status: family.soleAccount.map { status(for: $0.id) } ?? AccountStatus(),
            handle: { AnyView($0.highPriorityGesture(familyDragGesture(for: family))) }
        ) {
            DashboardCopyButton(provider: family.provider, active: hoveredFamilyID == family.id) {
                copyImage(of: family, plans: plans)
            }
        } account: { account in
            accountSection(account, in: family)
        }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                hoveredFamilyID = family.id
            } else if hoveredFamilyID == family.id {
                hoveredFamilyID = nil
            }
        }
    }

    /// An account with its menu and drag. In a one-account card it is only its rows: the header and the
    /// provider's menu stand in for its caption and menu, and there is no other account to reorder.
    @ViewBuilder
    private func accountSection(_ account: DashboardAccount, in family: DashboardFamily) -> some View {
        if family.soleAccount != nil {
            rows(of: account)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                DashboardAccountCaption(account: account, plan: dataStore.plan(for: account.id), status: status(for: account.id))
                    .highPriorityGesture(accountDragGesture(for: account, in: family))
                rows(of: account)
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

    /// The account's rows, each with its popover, right-click menu and drag.
    private func rows(of account: DashboardAccount) -> some View {
        ForEach(account.lines) { line in
            DashboardHoverRow(line: line, account: account, resetClaim: container.resetClaim(for: account.id))
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
    }

    /// A one-account provider's menu merges the account's commands into the provider's.
    private func familyMenu(_ family: DashboardFamily) -> DashboardMenus.Sections {
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

    /// Metrics the user hid from this account that have something to show.
    private func hiddenMetricIDs(for accountID: String) -> [String] {
        layout.orderedSupportedMetrics(for: accountID)
            .filter { !layout.isMetricEnabled($0.id) && dataStore.data(for: $0).hasData }
            .map(\.id)
    }

    // MARK: - Copying

    /// Copies an image of the provider's header and card at rest to the clipboard.
    private func copyImage(of family: DashboardFamily, plans: [String: String]) -> Bool {
        ShareCardRenderer.copy(ShareCardView(family: family, plans: plans, appearance: colorScheme))
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
            ShareCardRenderer.share(group: group, dataStore: dataStore, layout: layout, appearance: colorScheme)
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

    /// The account's visible line ids, read live so a drag sees each reorder it has already made.
    private func visibleLineIDs(for accountID: String) -> [String] {
        liveFamilies().flatMap(\.accounts).first { $0.id == accountID }?.lines.map(\.id) ?? []
    }

    private func metricDragGesture(for line: DashboardLine, accountID: String) -> some Gesture {
        reorderDragGesture(
            id: line.id,
            coordinateSpaceName: reorderSpaceName,
            frameStore: frameStore,
            active: $activeMetricID,
            lift: $reorderLift,
            makeLift: { value in
                let preview = DashboardMetricRow(model: line.data.dashboardRow())
                    .padding(.horizontal, DashboardGrid.cardPadding)
                    .liftedRowSurface()
                return ReorderLift.make(id: line.id, payload: .view(AnyView(preview)), value: value, frames: frameStore.frames)
            },
            orderedIDs: { visibleLineIDs(for: accountID) },
            reorder: { layout.reorderMetric(dragged: line.id, target: $0, in: accountID) }
        )
    }

    private static func familyFrameID(_ familyID: String) -> String { "family:\(familyID)" }

    private func accountDragGesture(for account: DashboardAccount, in family: DashboardFamily) -> some Gesture {
        reorderDragGesture(
            id: account.id,
            coordinateSpaceName: reorderSpaceName,
            frameStore: frameStore,
            active: $activeAccountID,
            lift: $reorderLift,
            makeLift: { value in
                let preview = DashboardAccountRows(account: account, plan: dataStore.plan(for: account.id))
                    .padding(DashboardGrid.cardPadding)
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
                let plans = plans(for: family)
                let preview = DashboardProviderSection(family: family, plans: plans) {
                    ProviderIcon(source: family.provider.icon, inset: 0.04)
                } account: { account in
                    DashboardAccountRows(account: account, plan: plans[account.id], showsCaption: family.soleAccount == nil)
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

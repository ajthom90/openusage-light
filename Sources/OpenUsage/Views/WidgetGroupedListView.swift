import SwiftUI

/// The dashboard display: one section per provider, holding each of its accounts (`DashboardFamily`).
/// Every account shows its plan beside its name and every metric that has data, fed by the same
/// `WidgetDataStore` the menu bar uses. Hovering a card shows its provider's quick links.
///
/// Right-click a provider's card for provider actions, an account for account actions, and a metric
/// line for metric actions. Everything reorders by dragging: a card by its header, an account by its
/// name line within its card, a metric line within its account.
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
        // One label column for the whole dashboard, so every bar starts at the same x.
        let labelWidth = DashboardMetricLine.labelWidth(
            for: families.flatMap(\.accounts).flatMap(\.lines).map(\.data.dashboardTitle)
        )
        VStack(alignment: .leading, spacing: PanelMetrics.sectionSpacing) {
            ForEach(families) { family in
                DashboardProviderCard(
                    family: family,
                    handle: { AnyView($0.highPriorityGesture(familyDragGesture(for: family, labelWidth: labelWidth))) }
                ) { account in
                    accountSection(
                        account,
                        group: groups.first { $0.provider.id == account.id },
                        family: family.id,
                        labelWidth: labelWidth
                    )
                }
                .contextMenu { providerMenu(family) }
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

    private func accountSection(
        _ account: DashboardAccount,
        group: ProviderGroup?,
        family: String,
        labelWidth: CGFloat
    ) -> some View {
        plainAccountSection(
            account,
            handle: {
                AnyView($0.highPriorityGesture(accountDragGesture(for: account, family: family, labelWidth: labelWidth)))
            }
        ) { line in
            metricLine(line, in: account, labelWidth: labelWidth)
        }
        .contextMenu { accountMenu(account, group: group) }
        .opacity(activeAccountID == account.id ? 0 : 1)
        .reorderFrame(id: account.id, in: .named(reorderSpaceName))
    }

    private func plainAccountSection<Line: View>(
        _ account: DashboardAccount,
        handle: @escaping (AnyView) -> AnyView = { $0 },
        @ViewBuilder line: @escaping (DashboardLine) -> Line
    ) -> some View {
        DashboardAccountSection(
            account: account,
            plan: dataStore.plan(for: account.id),
            notice: dataStore.headerNotice(for: account.id),
            refreshing: dataStore.refreshingProviderIDs.contains(account.id),
            staleness: dataStore.stalenessHint(for: account.id),
            handle: handle,
            line: line
        )
    }

    /// A metric line with its right-click menu. It drags to reorder within its account.
    private func metricLine(
        _ line: DashboardLine,
        in account: DashboardAccount,
        labelWidth: CGFloat
    ) -> some View {
        DashboardMetricLine(
            data: line.data,
            labelWidth: labelWidth,
            resetClaim: line.data.showsResetExpiries ? container.resetClaim(for: account.id) : nil
        )
        .contentShape(Rectangle())
        .opacity(activeMetricID == line.id ? 0 : 1)
        .highPriorityGesture(metricDragGesture(for: line, accountID: account.id, labelWidth: labelWidth))
        .contextMenu { lineMenu(line.descriptor, providerID: account.id) }
        .reorderFrame(id: line.id, in: .named(reorderSpaceName))
    }

    @ViewBuilder
    private func providerMenu(_ family: DashboardFamily) -> some View {
        Button("Refresh \(family.provider.displayName)") {
            Task {
                for account in family.accounts {
                    await dataStore.refreshOnUserRequest(providerID: account.id)
                }
            }
        }
        Button("Manage Accounts…") { openAccounts(nil) }
    }

    @ViewBuilder
    private func accountMenu(_ account: DashboardAccount, group: ProviderGroup?) -> some View {
        Button("Refresh") {
            Task { await dataStore.refreshOnUserRequest(providerID: account.id) }
        }
        Button("Rename Account") { renaming.begin(account.id) }
        Button("Edit Account…") { openAccounts(account.id) }
        if let group {
            Divider()
            Button("Share Screenshot") { _ = shareCard(group) }
        }
    }

    /// Hide a metric, star it for the menu bar, refresh its account, or open the account on the
    /// Accounts screen.
    @ViewBuilder
    private func lineMenu(_ descriptor: WidgetDescriptor, providerID: String) -> some View {
        Button("Hide") {
            layout.setMetricEnabled(descriptor.id, false)
        }
        if descriptor.pinnable {
            Button(layout.isPinned(descriptor.id) ? "Unstar" : "Star for menu bar") {
                if layout.isPinned(descriptor.id) {
                    layout.setPinned(false, for: descriptor.id)
                } else if layout.canPin(descriptor.id) {
                    layout.setPinned(true, for: descriptor.id)
                } else {
                    layout.notePinDenied(descriptor.id)
                }
            }
        }
        Divider()
        Button("Refresh") {
            Task { await dataStore.refreshOnUserRequest(providerID: providerID) }
        }
        Button("Edit Account…") { openAccounts(providerID) }
    }

    /// Opens the Accounts screen, on one account's page when `providerID` is set.
    private func openAccounts(_ providerID: String?) {
        withAnimation(Motion.modeSwitch) {
            layout.customizeProviderID = providerID
            layout.isEditing = true
        }
    }

    /// Renders the account's branded share card and copies the PNG to the clipboard, in the popover's
    /// own appearance. The footer's "Share Screenshot" submenu uses the same path.
    private func shareCard(_ group: ProviderGroup) -> Bool {
        ShareCardRenderer.share(
            group: group,
            dataStore: dataStore,
            layout: layout,
            appearance: colorScheme
        )
    }

    private func metricDragGesture(for line: DashboardLine, accountID: String, labelWidth: CGFloat) -> some Gesture {
        reorderDragGesture(
            id: line.id,
            coordinateSpaceName: reorderSpaceName,
            frameStore: frameStore,
            active: $activeMetricID,
            lift: $reorderLift,
            makeLift: { value in
                let preview = DashboardMetricLine(data: line.data, labelWidth: labelWidth)
                    .padding(.horizontal, 4)
                    .liftedRowSurface()
                return ReorderLift.make(id: line.id, payload: .view(AnyView(preview)), value: value, frames: frameStore.frames)
            },
            orderedIDs: { visibleLineIDs(for: accountID) },
            reorder: { layout.reorderMetric(dragged: line.id, target: $0, in: accountID) }
        )
    }

    // MARK: - Account and card reordering

    private static func familyFrameID(_ familyID: String) -> String { "family:\(familyID)" }

    private func liveFamilies() -> [DashboardFamily] {
        DashboardFamily.make(groups: layout.displayGroups, line: resolveLine)
    }

    private func accountDragGesture(for account: DashboardAccount, family: String, labelWidth: CGFloat) -> some Gesture {
        reorderDragGesture(
            id: account.id,
            coordinateSpaceName: reorderSpaceName,
            frameStore: frameStore,
            active: $activeAccountID,
            lift: $reorderLift,
            makeLift: { value in
                let preview = plainAccountSection(account) {
                    DashboardMetricLine(data: $0.data, labelWidth: labelWidth)
                }
                .padding(.vertical, DashboardBox.verticalPadding)
                .liftedRowSurface()
                return ReorderLift.make(id: account.id, payload: .view(AnyView(preview)), value: value, frames: frameStore.frames)
            },
            orderedIDs: { liveFamilies().first { $0.id == family }?.accounts.map(\.id) ?? [] },
            reorder: { layout.reorderProvider(dragged: account.id, target: $0) }
        )
    }

    private func familyDragGesture(for family: DashboardFamily, labelWidth: CGFloat) -> some Gesture {
        let frameID = Self.familyFrameID(family.id)
        return reorderDragGesture(
            id: frameID,
            coordinateSpaceName: reorderSpaceName,
            frameStore: frameStore,
            active: $activeFamilyID,
            lift: $reorderLift,
            makeLift: { value in
                let preview = DashboardProviderCard(family: family) {
                    plainAccountSection($0) {
                        DashboardMetricLine(data: $0.data, labelWidth: labelWidth)
                    }
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

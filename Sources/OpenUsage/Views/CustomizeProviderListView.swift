import SwiftUI

/// The Customize provider list (L1): every account as a row, in the user's saved order.
struct CustomizeProviderListView: View {
    @Environment(LayoutStore.self) private var layout
    let reorderSpaceName: String
    @Binding var reorderLift: ReorderLift?
    let frameStore: ReorderFrameStore

    @State private var activeProviderID: String?
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular

    private var orderedRows: [ProviderRow] { layout.customizeProviderRows }

    var body: some View {
        VStack(alignment: .leading, spacing: density.sectionSpacing) {
            VStack(spacing: 0) {
                ForEach(orderedRows) { row in
                    providerRow(row)
                }
            }
            .cardSurface()
            // App behavior/appearance options live on the other screen; catch users who came here
            // hunting for them once they've scanned past the provider list.
            ScreenCrossLinkRow(
                systemImage: "gearshape",
                title: "Settings",
                subtitle: "Notifications, appearance and more",
                destination: .settings
            )
        }
        .animation(Motion.spring, value: orderedRows.map(\.id))
    }

    private func providerRow(_ row: ProviderRow) -> some View {
        ProviderListRow(
            provider: row.provider,
            metricCount: row.metricCount,
            handle: { AnyView($0.highPriorityGesture(providerDragGesture(for: row))) },
            onOpen: { withAnimation(Motion.spring) { layout.customizeProviderID = row.id } }
        )
        .opacity(activeProviderID == row.id ? 0 : 1)
        .reorderFrame(id: row.id, in: .named(reorderSpaceName))
    }

    private func providerDragGesture(for row: ProviderRow) -> some Gesture {
        reorderDragGesture(
            id: row.id,
            coordinateSpaceName: reorderSpaceName,
            frameStore: frameStore,
            active: $activeProviderID,
            lift: $reorderLift,
            makeLift: { makeProviderLift(for: row, value: $0) },
            // Hit-test only enabled providers (the set `reorderProvider` can actually move); disabled
            // rows keep their tail position and aren't reorder targets.
            orderedIDs: { layout.customizeGroups.map(\.provider.id) },
            reorder: { layout.reorderProvider(dragged: row.id, target: $0) }
        )
    }

    private func makeProviderLift(for row: ProviderRow, value: DragGesture.Value) -> ReorderLift? {
        ReorderLift.make(
            id: row.id,
            payload: .customizeProviderRow(provider: row.provider, metricCount: row.metricCount),
            value: value,
            frames: frameStore.frames
        )
    }
}

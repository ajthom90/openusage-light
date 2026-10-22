import SwiftUI

/// The Accounts list (L1): every account in the user's saved order, grouped in one card the way
/// Settings groups its rows, with Add Account below. Click a row to open that account (L2);
/// drag its grip to reorder the accounts, which reorders the dashboard too.
struct AccountListView: View {
    @Environment(AppContainer.self) private var container
    @Environment(LayoutStore.self) private var layout
    let reorderSpaceName: String
    @Binding var reorderLift: ReorderLift?
    let frameStore: ReorderFrameStore

    @State private var activeProviderID: String?
    @State private var isAddingAccount = false
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular

    var body: some View {
        let providers = layout.orderedProviders()
        VStack(alignment: .leading, spacing: density.sectionSpacing) {
            if !providers.isEmpty {
                VStack(spacing: 0) {
                    ForEach(providers) { provider in
                        accountRow(provider)
                    }
                }
                .cardSurface()
            }
            addAccountButton
        }
        .animation(Motion.spring, value: providers.map(\.id))
        .sheet(isPresented: $isAddingAccount) {
            AddAccountSheet(store: container.accounts)
        }
    }

    private var addAccountButton: some View {
        Button {
            isAddingAccount = true
        } label: {
            Label("Add Account", systemImage: "plus")
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
        }
        .glassButtonStyle(prominent: true)
        .controlSize(.large)
    }

    private func accountRow(_ provider: Provider) -> some View {
        AccountListRow(
            provider: provider,
            handle: { AnyView($0.highPriorityGesture(accountDragGesture(for: provider))) },
            onOpen: { withAnimation(Motion.spring) { layout.customizeProviderID = provider.id } }
        )
        .opacity(activeProviderID == provider.id ? 0 : 1)
        .reorderFrame(id: provider.id, in: .named(reorderSpaceName))
    }

    private func accountDragGesture(for provider: Provider) -> some Gesture {
        reorderDragGesture(
            id: provider.id,
            coordinateSpaceName: reorderSpaceName,
            frameStore: frameStore,
            active: $activeProviderID,
            lift: $reorderLift,
            makeLift: { value in
                ReorderLift.make(
                    id: provider.id,
                    payload: .accountRow(provider: provider),
                    value: value,
                    frames: frameStore.frames
                )
            },
            orderedIDs: { layout.orderedProviders().map(\.id) },
            reorder: { layout.reorderProvider(dragged: provider.id, target: $0) }
        )
    }
}

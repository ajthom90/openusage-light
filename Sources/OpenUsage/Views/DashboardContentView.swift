import SwiftUI

/// The dashboard-only scrolling content. Screen switching, panel sizing, fixed bars, keyboard handling,
/// and close/reset behavior stay with `DashboardView`.
struct DashboardContentView: View {
    let container: AppContainer
    let layout: LayoutStore
    let reorderSpaceName: String

    @Binding var reorderLift: ReorderLift?
    @Binding var scrollPosition: ScrollPosition

    @State private var isAddingAccount = false
    @Environment(\.popoverSurfaceTreatment) private var treatment

    var body: some View {
        PopoverScrollView {
            widgetContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollPosition($scrollPosition)
        .sheet(isPresented: $isAddingAccount) {
            AddAccountSheet(store: container.accounts)
        }
    }

    @ViewBuilder
    private var widgetContent: some View {
        if layout.displayGroups.isEmpty {
            EmptyDashboardView { isAddingAccount = true }
                .padding(PanelMetrics.margin)
        } else {
            WidgetGroupedListView(
                reorderSpaceName: reorderSpaceName,
                reorderLift: $reorderLift
            )
            .padding(.vertical, DashboardSpacing.listPadding)
            .background {
                if treatment == .translucent {
                    Theme.traySurface.opacity(Theme.translucentTrayOpacity)
                }
            }
        }
    }
}

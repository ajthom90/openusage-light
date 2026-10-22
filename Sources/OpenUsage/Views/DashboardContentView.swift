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

    var body: some View {
        PopoverScrollView {
            VStack(alignment: .leading, spacing: 0) {
                widgetContent
            }
            .padding(PanelMetrics.margin)
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
        } else {
            WidgetGroupedListView(
                reorderSpaceName: reorderSpaceName,
                reorderLift: $reorderLift
            )
        }
    }
}

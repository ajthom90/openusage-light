import SwiftUI

/// The Accounts screen, a two-level master/detail: the account list (L1) or, when
/// `layout.customizeProviderID` is set, that account's detail (L2). The two slide horizontally — L2
/// enters from the trailing edge, L1 returns from the leading edge — on the same spring. The back
/// chevron (handled in `PopoverTopBar`) is context-aware: L2 → L1, L1 → dashboard.
///
/// Reordering uses `DragGesture` plus local row geometry, kept inside the menu-bar popover instead
/// of SwiftUI's pasteboard-backed drag/drop (unreliable here). The router owns the scroll view and
/// the reorder-frame map; L1 and L2 read it for their drag hit-testing and emit frames via
/// `.reorderFrame`. The `customizeProviderID` route lives in `LayoutStore` so the popover-closed
/// reset and the Esc handler drive the same state.
struct AccountsView: View {
    @Environment(LayoutStore.self) private var layout
    let reorderSpaceName: String
    @Binding var reorderLift: ReorderLift?

    @State private var frameStore = ReorderFrameStore()

    var body: some View {
        PopoverScrollView {
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
        }
        .onPreferenceChange(ReorderFramePreferenceKey.self) { frameStore.frames = $0 }
        // The transient star/denial pill floats above the detail content — the same capsule style as
        // the dashboard's "Copied to clipboard" share pill. Green for a successful star/unstar, orange
        // for the per-provider cap denial.
        .overlay(alignment: .bottom) {
            if layout.customizationNotice != nil {
                customizationNoticePill
                    .padding(.bottom, 12)
            }
        }
        .animation(Motion.spring, value: layout.customizationNotice)
        .animation(Motion.spring, value: layout.customizationNoticeTrigger)
    }

    private var customizationNoticePill: some View {
        let isNotice = layout.customizationNoticeTone == .notice
        return TransientPill(
            systemImage: isNotice ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
            text: layout.customizationNotice ?? "",
            tint: isNotice ? Theme.notice : Theme.positive,
            trigger: layout.customizationNoticeTrigger,
            showsShadow: false
        )
    }

    /// Both levels share one ZStack so the outgoing and incoming level overlap while they slide instead
    /// of stacking, and each fades as it moves: the Liquid Glass Add Account button is drawn by the
    /// system glass layer, which does not follow a bare offset, so without the fade it lingers in place
    /// until the transition ends.
    private var content: some View {
        ZStack(alignment: .top) {
            level
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var level: some View {
        if let id = layout.customizeProviderID {
            AccountDetailView(
                providerID: id,
                reorderSpaceName: reorderSpaceName,
                reorderLift: $reorderLift,
                frameStore: frameStore
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            AccountListView(
                reorderSpaceName: reorderSpaceName,
                reorderLift: $reorderLift,
                frameStore: frameStore
            )
            .transition(.move(edge: .leading).combined(with: .opacity))
        }
    }
}

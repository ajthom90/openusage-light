import SwiftUI

/// A metric row on the live dashboard: the row with its one hover affordance. It shows nothing under the
/// pointer itself; after the hover dwell a popover opens below it — the account's resets, soonest first,
/// with this row's own emphasized — or, on the Limit Resets row, the resets timeline where a reset is
/// claimed. A value row with nothing to list opens nothing. Rows with a clock re-render every 30 s so
/// their colour and reset stay live.
struct DashboardHoverRow: View {
    let line: DashboardLine
    let account: DashboardAccount
    /// The Limit Resets row's claim seam, `nil` where resets can't be claimed.
    var resetClaim: ResetClaimService?

    @Environment(\.reduceAnimations) private var reduceAnimations
    @State private var hover = HoverPopoverState()

    var body: some View {
        Group {
            if line.data.resetsAt != nil || !line.data.expiriesAt.isEmpty {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    DashboardMetricRow(model: line.data.dashboardRow(now: context.date))
                }
            } else {
                DashboardMetricRow(model: line.data.dashboardRow())
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active = phase { hover.inlineHover(true) } else { hover.inlineHover(false) }
        }
        .motionAwareHoverPopover(
            isPresented: Binding(
                get: { hover.isPresented && hasPopover },
                set: { if !$0 { hover.dismiss() } }
            ),
            reduceAnimations: reduceAnimations
        ) {
            popover
        }
        // A refresh can replace the resets while the popover is open; drop it so it never lingers over a
        // stale timeline, unless the claim flow pinned it (the claim's own refresh changes the resets).
        .onChange(of: line.data.expiriesAt) { _, _ in
            if !hover.isPinned { hover.dismiss() }
        }
        .onDisappear { hover.dismiss() }
    }

    private var hasPopover: Bool {
        line.data.showsResetExpiries || !AccountResetsTimeline.nodes(for: account.lines, hovered: line.id).isEmpty
    }

    @ViewBuilder
    private var popover: some View {
        if line.data.showsResetExpiries {
            RateLimitResetsDetail(
                count: line.data.resetCreditCount,
                expiries: line.data.expiriesAt,
                onHoverChange: { inside in hover.detailHover(inside) },
                onPinChange: { pinned in hover.setPinned(pinned) },
                claim: resetClaim.flatMap { service in
                    service.isClaimable ? { expiry, redeemRequestID in
                        await service.claim(creditExpiringAt: expiry, redeemRequestID: redeemRequestID)
                    } : nil
                },
                confirmDetail: resetClaim?.confirmDetail
            )
        } else {
            AccountResetsPopover(
                title: account.provider.fullName,
                nodes: AccountResetsTimeline.nodes(for: account.lines, hovered: line.id),
                onHoverChange: { inside in hover.detailHover(inside) }
            )
        }
    }
}

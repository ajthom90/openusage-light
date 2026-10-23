import SwiftUI

/// "↺ 2": the account's available rate-limit resets. Hovering or clicking opens the resets timeline,
/// where a reset can be claimed. The chip takes the color of the soonest expiry (blue, then orange
/// within 7 days, red within 48 hours) so an expiring reset stands out.
struct ResetCountChip: View {
    let data: WidgetData
    var claim: ResetClaimService?

    @Environment(\.reduceAnimations) private var reduceAnimations
    @State private var hover = HoverPopoverState()

    var body: some View {
        let tint = Theme.severityColor(data.expirySeverity())
        Button { hover.present() } label: {
            HStack(spacing: 3) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 9, weight: .bold))
                Text("\(data.resetCreditCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(Capsule().fill(tint.opacity(hover.overInline || hover.isPresented ? 0.24 : 0.14)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: hover.overInline)
        .onContinuousHover { phase in
            if case .active = phase { hover.inlineHover(true) } else { hover.inlineHover(false) }
        }
        .motionAwareHoverPopover(
            isPresented: Binding(
                get: { hover.isPresented },
                set: { if !$0 { hover.dismiss() } }
            ),
            reduceAnimations: reduceAnimations
        ) {
            RateLimitResetsDetail(
                count: data.resetCreditCount,
                expiries: data.expiriesAt,
                onHoverChange: { inside in hover.detailHover(inside) },
                onPinChange: { pinned in hover.setPinned(pinned) },
                claim: claim.flatMap { service in
                    service.isClaimable ? { expiry, redeemRequestID in
                        await service.claim(creditExpiringAt: expiry, redeemRequestID: redeemRequestID)
                    } : nil
                },
                confirmDetail: claim?.confirmDetail
            )
        }
        // A refresh can replace the resets while the popover is open; drop it so it never lingers over a
        // stale timeline, unless the claim flow pinned it (the claim's own refresh changes the resets).
        .onChange(of: data.expiriesAt) { _, _ in
            if !hover.isPinned { hover.dismiss() }
        }
        .onDisappear { hover.dismiss() }
        .accessibilityLabel(data.resetCreditCount == 1 ? "1 reset available" : "\(data.resetCreditCount) resets available")
    }
}

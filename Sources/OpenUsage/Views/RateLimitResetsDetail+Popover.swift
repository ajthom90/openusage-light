import SwiftUI

extension View {
    /// Makes a Resets line the trigger for its resets timeline: hovering the line (after the usual dwell)
    /// or clicking it opens `RateLimitResetsDetail` centred under the line, where a reset can be claimed.
    /// The line lights up while the pointer is over it or its popover is open, over the same rect that
    /// takes the click.
    func rateLimitResetsPopover(data: WidgetData, claim: ResetClaimService?) -> some View {
        modifier(RateLimitResetsPopover(data: data, claim: claim))
    }
}

private struct RateLimitResetsPopover: ViewModifier {
    let data: WidgetData
    let claim: ResetClaimService?

    @Environment(\.reduceAnimations) private var reduceAnimations
    @State private var hover = HoverPopoverState()

    func body(content: Content) -> some View {
        Button { hover.present() } label: {
            content
                .contentShape(Rectangle())
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.fill.quaternary)
                        .padding(.horizontal, -5)
                        .opacity(hover.overInline || hover.isPresented ? 1 : 0)
                }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: hover.overInline || hover.isPresented)
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
        .accessibilityHint("Shows when each reset expires")
    }
}

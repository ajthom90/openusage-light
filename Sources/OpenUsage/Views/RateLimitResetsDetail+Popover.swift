import SwiftUI

extension View {
    /// Makes the Resets value ("2 available") the trigger for its resets timeline: hovering it (after the
    /// usual dwell) or clicking it opens `RateLimitResetsDetail` anchored on the value, where a reset can
    /// be claimed. While the pointer is over the value or its popover is open, a quaternary chip lights up
    /// behind the value alone, the inline highlight OpenUsage uses for its resets and spend values.
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
        let isLit = hover.overInline || hover.isPresented
        Button { hover.present() } label: {
            content
                // Negative insets hug the value without changing the line's height.
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quaternary)
                        .padding(.horizontal, -7)
                        .padding(.vertical, -4)
                        .opacity(isLit ? 1 : 0)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: isLit)
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

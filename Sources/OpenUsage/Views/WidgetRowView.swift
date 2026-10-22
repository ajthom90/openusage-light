import SwiftUI

/// One metric as a row inside a provider's grouped list container. The provider icon is drawn once in the
/// section header (not per row), so a row shows only the metric. Two layouts:
/// - **Bounded** (`limit != nil`, meter row): a label line (right-aligned flame + run-out time when
///   projected to run out before reset, or "~3% spare" when cutting it close), then a full-width
///   capsule meter (color = pace verdict; in the amber state a tick splits the projected spare
///   cushion off the bar; hovering shows the verdict), then a primary text row ("50% left" ⟷ "Resets in 4d 17h").
///   Mirrors the original OpenUsage card.
/// - **Unbounded** (`limit == nil`, text-only row): **no bar**. Label on the left, a single right-aligned
///   descriptive line ("1,503 left") and an optional secondary line ("on-device estimate").
/// Rows size to their own content (variable height). Same `WidgetData` the menu bar uses — only layout differs.
struct WidgetRowView: View {
    let data: WidgetData
    /// Flips the global relative/absolute reset display. Supplied where the row has the data store
    /// (the dashboard list); `nil` in static contexts like the drag-reorder preview, where the reset
    /// label stays plain text.
    var onToggleResetDisplay: (() -> Void)?
    /// Flips the global Used/Left meter style — the headline's counterpart to the reset toggle.
    /// Same supply rules as `onToggleResetDisplay`.
    var onToggleMeterStyle: (() -> Void)?
    /// True when this text-only row sits directly under another text-only row. Rows don't know
    /// their neighbors — the list supplies it — and it pulls consecutive one-liners into a single
    /// cluster.
    var condensedTop: Bool = false
    /// Backs the resets popover's claim flow on a Rate Limit Resets row. `nil` everywhere else (other
    /// rows, share renders, reorder previews), which renders the timeline read-only.
    var resetClaim: ResetClaimService?

    @Environment(\.reduceAnimations) private var reduceAnimations
    @State private var resetsHover = HoverPopoverState()

    /// The share card's type: a 13 pt semibold label over 12 pt (callout) supporting text.
    private let labelFont = Font.body.weight(.semibold)
    private let supportingFont = Font.callout
    /// Vertical padding of a bar row, a text row, and a text row under another text row.
    private static let barRowPadding: CGFloat = 10
    private static let textRowPadding: CGFloat = 6
    private static let condensedTextRowTopPadding: CGFloat = 2

    var body: some View {
        // A row with a concrete reset date derives time-sensitive state (reset countdown, pace marker,
        // "Runs out in …") from the current clock, so it re-renders on a 30s tick — the cadence the
        // original app uses — instead of waiting for the next data refresh. TimelineView only schedules
        // ticks while the popover is actually visible. Rows without a reset date are static.
        Group {
            if data.resetsAt != nil || !data.expiriesAt.isEmpty {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    rowContent
                }
            } else {
                rowContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        // Bar rows are multi-line and earn breathing room; single-line text rows (Today / Yesterday /
        // Last 30 Days) stay tighter so consecutive ones read as a cluster, not evenly-spaced
        // full-height rows. This differentiation — not the fonts — is what kills the "jumpy" rhythm.
        // A text row pulls up against a preceding text row (`condensedTop`).
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
    }

    private var topPadding: CGFloat {
        if data.isBounded { return Self.barRowPadding }
        return condensedTop ? Self.condensedTextRowTopPadding : Self.textRowPadding
    }

    private var bottomPadding: CGFloat {
        data.isBounded ? Self.barRowPadding : Self.textRowPadding
    }

    @ViewBuilder
    private var rowContent: some View {
        if data.isBounded {
            boundedRow
        } else {
            unboundedRow
        }
    }

    /// Bounded: label (+ run-out warning) → meter → primary text row.
    /// The label, bar, and reading are one perceptual unit, so they sit on the tight step of the
    /// grid (`rowInnerSpacing`); the row's vertical padding provides the separation from
    /// neighboring rows.
    private var boundedRow: some View {
        let state = data.meterState()
        return VStack(alignment: .leading, spacing: 4) {
            boundedLabelRow(state)
            meter(state)
            primaryTextRow
        }
    }

    /// Label with the pace warning right-aligned on the same line — one slot, escalating with the
    /// `MeterState`. Spent: a flame + "Limit reached",
    /// the terminal state that outranks any pace projection. Running out: a flame + projected
    /// run-out time, read as "Limit in 3h 45m" ⟷ "Limit today at 11:49 PM" (following the global
    /// countdown/exact mode) — clicking the time flips the global mode like the reset label. Close
    /// to limit: a quiet "~3% spare" — the cushion projected at reset. Healthy / level / no-data:
    /// nothing unless "always show pacing" surfaces projection on blue. Only the flame carries
    /// flame carries the severity color — tint on glass is reserved for the symbol while copy
    /// stays secondary like the row's other supporting text; the bar below carries the color.
    /// Hovering shows the pace projection at reset. The warning gets the space; the title truncates.
    private func boundedLabelRow(_ state: WidgetData.MeterState) -> some View {
        HStack(spacing: 6) {
            Text(data.title)
                .font(labelFont)
                .foregroundStyle(.primary)
                .lineLimit(1)
            warning(state)
        }
    }

    /// The single escalating warning slot, switching exhaustively over the state so the copy can
    /// never contradict the bar. The flame cases share one builder; the amber and (always-show-pacing)
    /// blue cases are plain text.
    @ViewBuilder
    private func warning(_ state: WidgetData.MeterState) -> some View {
        switch state {
        case .spent:
            flameWarning(text: "Limit reached", state: state, accessibility: "Limit reached")
        case .runningOut(let eta, _):
            // `eta == nil` is the float-edge case: the flame stands alone (the projection lives in
            // the tooltip), rather than printing a misleading time. A shown time reads "Limit in 3h
            // 45m" (or the exact "Limit today at …"), carrying its own verb and following the global
            // countdown/exact mode, so — exactly like the reset label — clicking it flips that mode
            // (lifted reorder previews pass no toggle and render it inert).
            flameWarning(text: eta, state: state,
                         accessibility: eta ?? "Will reach limit",
                         action: eta == nil ? nil : onToggleResetDisplay)
        case .closeToLimit(let spare, _):
            Spacer(minLength: 8)
            Text(spare)
                .font(supportingFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .hoverTooltip(state.tooltip)
        case .healthy where data.alwaysShowPacing:
            // "Always show pacing" surfaces the projection on the otherwise-silent on-track row: the
            // same quiet secondary note as the amber case, but the cushion ("~33% left at reset")
            // rather than the spare. No flame (blue isn't a warning) and no hover tooltip — the copy
            // already *is* the projection the amber case hides in its tooltip.
            if let projection = state.tooltip {
                Spacer(minLength: 8)
                Text(projection)
                    .font(supportingFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        case .noData, .healthy, .level:
            EmptyView()
        }
    }

    /// Flame icon + optional label text, carrying the state's projection tooltip — shared by the
    /// spent and running-out cases. Only the flame is severity-tinted; the copy stays secondary
    /// (tint on glass is reserved for the symbol). An optional `action` wraps the warning in a
    /// plain button (the run-out time's countdown/exact toggle).
    @ViewBuilder
    private func flameWarning(text: String?, state: WidgetData.MeterState,
                              accessibility: String, action: (() -> Void)? = nil) -> some View {
        Spacer(minLength: 8)
        let label = HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .font(.subheadline)
                .foregroundStyle(severityColor(state.severity))
                .accessibilityHidden(true) // the warning text alongside carries the message
            if let text {
                Text(text)
                    .font(supportingFont)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .foregroundStyle(.secondary)
        .hoverTooltip(state.tooltip)
        .accessibilityLabel(accessibility)

        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }

    /// Bar/copy color for a severity, or the inactive gray when there's none (the no-data track).
    private func severityColor(_ severity: WidgetData.MeterSeverity?) -> AnyShapeStyle {
        severity.map(Theme.meterFill) ?? AnyShapeStyle(Color.secondary)
    }

    /// Primary line under the bar: value+mode word on the left ("50% left"), reset/limit context on
    /// the right. The headline is the Used/Left toggle (click to flip the global meter style, with
    /// the opposite reading in its tooltip) — the exact counterpart of the reset label's toggle.
    private var primaryTextRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            headlineText
            Spacer(minLength: 8)
            trailingContext
        }
        .font(supportingFont)
        .lineLimit(1)
    }

    // The headline value is the row's payload — the number the user opened the popover to read —
    // so it sits at `.primary` (vibrant full-contrast on the popover glass); the surrounding
    // context (reset countdown, deficit) stays `.secondary`.
    @ViewBuilder
    private var headlineText: some View {
        if data.hasMeterStyleToggle, let onToggleMeterStyle {
            Button(action: onToggleMeterStyle) {
                Text(data.headline)
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }
            .buttonStyle(.plain)
            .hoverTooltip(data.meterStyleTooltip)
        } else {
            Text(data.headline)
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
        }
    }

    /// Reset/limit context on the trailing edge. When it's a concrete reset countdown it becomes a
    /// click target that flips the global relative/absolute mode (with the opposite format in its
    /// tooltip), mirroring the original. Otherwise it's plain text.
    @ViewBuilder
    private var trailingContext: some View {
        if let text = data.boundedTrailingText() {
            if data.hasResetLabel(), let onToggleResetDisplay {
                Button(action: onToggleResetDisplay) {
                    Text(text).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .hoverTooltip(data.resetTooltip())
            } else {
                Text(text).foregroundStyle(.secondary)
                    .hoverTooltip(data.resetTooltip())
            }
        }
    }

    /// Unbounded: no bar. Label on the left, with a single right-aligned descriptive line ("1,503 left")
    /// and an optional secondary line ("on-device estimate") beneath it.
    private var unboundedRow: some View {
        unboundedRowContent
            // A refresh can replace the resets (count and expiries) while the popover is open; drop it so
            // it never lingers over a stale timeline — except while the claim flow has the popover pinned:
            // the claim's own refresh is what changes the resets, and dismissing on it would close the
            // popover before the result banner ever renders. The pinned popover re-renders from the new
            // data instead (the detail view reconciles its own state).
            .onChange(of: data.expiriesAt) { _, _ in
                if !resetsHover.isPinned { resetsHover.dismiss() }
            }
            .onDisappear { resetsHover.dismiss() }
    }

    /// The value column reveals the resets popover on hover, so it lights up under the pointer the way a
    /// Finder / System Settings list row does — the native cue that "this is a target." Lit the moment the
    /// pointer arrives (`overInline`, before the reveal dwell) and held lit while the popover is open, so
    /// the value reads as the popover's source. Both flags live on `resetsHover`, so the panel's close
    /// path (`dismissAll`) clears the highlight even though this view's state survives `orderOut`.
    private var showValueHighlight: Bool {
        hasResetsPopover && (resetsHover.overInline || resetsHover.isPresented)
    }

    /// Whether the value column reveals the resets popover. The resets row qualifies even at
    /// "0 available" (empty `expiriesAt`), so its empty-state popover stays reachable — but only with real
    /// data: a "No data" tile must not open a popover that reads as "zero credits".
    private var hasResetsPopover: Bool {
        data.showsResetExpiries && data.hasData
    }

    private var unboundedRowContent: some View {
        HStack(alignment: .center, spacing: 10) {
            labelColumn
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    expiryStatusDot
                    Text(data.unboundedDetail)
                        .font(supportingFont)
                        .foregroundStyle(.primary) // the value is the row's payload — match the bounded headline
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        // The resets row drops its figures tooltip: the timeline popover replaces it,
                        // and a text bubble and a popover fighting over one hover read as two surfaces.
                        .hoverTooltip(hasResetsPopover ? nil : data.unboundedValueTooltip)
                }
                if let subtitle = data.unboundedSubtitle {
                    // Secondary, not tertiary: the subtitle is informational ("on-device estimate"),
                    // and tertiary is reserved for inactive content on glass.
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(.trailing)
            // A quaternary chip behind the value — the app's subtle-fill token, in the shared 6pt
            // continuous corner — signals the value is interactive before the popover even opens.
            // Negative-inset so it hugs the figure without changing the row's height, and a quick opacity
            // fade in/out matches macOS hover states.
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary)
                    .padding(.horizontal, -7)
                    .padding(.vertical, -4)
                    .opacity(showValueHighlight ? 1 : 0)
            }
            .animation(.easeOut(duration: 0.12), value: showValueHighlight)
            // Both the hover trigger and the popover anchor live on the value column, not the whole row:
            // hovering the label (or empty gap) shouldn't reveal the timeline — only the figure it
            // explains should — and the arrow then centers on that figure.
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard hasResetsPopover else {
                    resetsHover.dismiss()
                    return
                }
                if case .active = phase {
                    resetsHover.inlineHover(true)
                } else {
                    resetsHover.inlineHover(false)
                }
            }
            .motionAwareHoverPopover(
                isPresented: Binding(
                    get: { hasResetsPopover && resetsHover.isPresented },
                    // A click-outside dismiss removes the detail view without an `.ended` hover event,
                    // so a plain assignment would strand `overDetail == true` and block future hides.
                    set: { if !$0 { resetsHover.dismiss() } }
                ),
                reduceAnimations: reduceAnimations
            ) {
                RateLimitResetsDetail(
                    count: data.resetCreditCount,
                    expiries: data.expiriesAt,
                    onHoverChange: { inside in resetsHover.detailHover(inside) },
                    onPinChange: { pinned in resetsHover.setPinned(pinned) },
                    // An account whose provider has nothing to claim right now (a Claude account with no
                    // next grant) shows the read-only timeline.
                    claim: resetClaim.flatMap { service in
                        service.isClaimable ? { expiry, redeemRequestID in
                            await service.claim(creditExpiringAt: expiry, redeemRequestID: redeemRequestID)
                        } : nil
                    },
                    confirmDetail: resetClaim?.confirmDetail
                )
            }
        }
    }

    /// Small blue/yellow/red status dot shown just before the value when the row carries reset-credit
    /// expiries — colored by the soonest expiry. The per-credit detail (which credits, expiring when)
    /// lives in the resets popover the value column now reveals on hover, so the dot carries no tooltip
    /// of its own. Renders nothing when no credit is available (an empty `expiriesAt`).
    @ViewBuilder
    private var expiryStatusDot: some View {
        if let severity = data.expirySeverity() {
            Circle()
                .fill(severityColor(severity))
                .frame(width: 6, height: 6)
                .accessibilityLabel(expiryStatusAccessibilityLabel(severity))
        }
    }

    private func expiryStatusAccessibilityLabel(_ severity: WidgetData.MeterSeverity) -> String {
        switch severity {
        case .normal: return "Reset credits expire in more than 7 days"
        case .warning: return "A reset credit expires within 7 days"
        case .critical: return "A reset credit expires within 48 hours"
        }
    }

    private var labelColumn: some View {
        HStack(spacing: 4) {
            Text(data.title)
                // Same point size as the trailing value so the single-line row reads tight;
                // semibold alone keeps the name/value hierarchy.
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// Full-width capsule meter; see `UsageMeterBar`.
    private func meter(_ state: WidgetData.MeterState) -> some View {
        UsageMeterBar(data: data, state: state)
    }
}

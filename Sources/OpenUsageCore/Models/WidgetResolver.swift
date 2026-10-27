import Foundation

/// Turns a provider's latest snapshot into the display model for one dashboard row. Platform-neutral,
/// so every surface (the Mac panel, a Windows popover) builds its rows the same way.
package enum WidgetResolver {
    /// The row's data: the snapshot line the descriptor names, or a no-data placeholder when the
    /// snapshot has no such line (the row then renders "No data" instead of inventing usage).
    package static func data(
        for descriptor: WidgetDescriptor,
        snapshot: ProviderSnapshot?,
        displayMode: WidgetDisplayMode,
        resetDisplayMode: ResetDisplayMode
    ) -> WidgetData {
        var result: WidgetData
        if let snapshot, let line = snapshot.line(label: descriptor.metricLabel),
           let data = resolve(line, descriptor: descriptor) {
            result = data
        } else {
            result = descriptor.sample
            result.hasData = false
        }
        // Inert for unbounded rows (limit == nil), whose displayed value ignores displayMode.
        result.displayMode = displayMode
        result.resetDisplayMode = resetDisplayMode
        return result
    }

    private static func resolve(_ line: MetricLine, descriptor: WidgetDescriptor) -> WidgetData? {
        switch line {
        case .progress(_, let used, let limit, let format, let resetsAt, let periodDurationMs, _):
            // A percent meter is a bounded 0...100 domain; sanitize an out-of-range sample (a provider
            // reporting a negative or >100 utilization) here, at the single construction choke point
            // every provider funnels through, so no surface — the row, the menu bar — can
            // render "-5%" or "105%". For percent the limit is always 100, so clamping `used` also
            // keeps the meter's spent verdict intact (>=100 still reads spent). Non-percent
            // meters keep their raw `used`: a dollar/count overage (used > limit) is real and is
            // conveyed by the meter's spent state rather than hidden.
            let normalizedUsed = format == .percent ? ProviderParse.clampPercent(used) : used
            var result = WidgetData(
                title: descriptor.sample.title,
                icon: descriptor.sample.icon,
                kind: format.metricKind,
                used: normalizedUsed,
                limit: limit,
                countSuffix: format.countSuffix,
                valuePrefix: descriptor.sample.valuePrefix,
                resetsAt: resetsAt,
                periodDurationMs: periodDurationMs
            )
            // Descriptor opt-in (session-window meters read "Not started" when unused); the fresh
            // `.progress` result doesn't start from the sample, so carry the signal explicitly.
            result.sessionStartSignal = descriptor.sample.sessionStartSignal
            return result
        case .text:
            // Text lines carry provider notices; no dashboard descriptor consumes
            // them. Numeric widgets use typed progress/values lines and must never parse display text.
            return nil
        case .values(_, let values, _, let expiriesAt):
            // The number is carried raw — no regex re-parse. Presentation (title, icon, selection,
            // trailing word) comes from the descriptor's sample; the live numbers come from the line.
            var data = descriptor.sample
            data.values = values
            // A `.values` line is unbounded by definition (see `MetricLine`), so it never renders as a
            // meter even when the descriptor template carries a placeholder limit — e.g. Claude's
            // `claude.extra` is `boundedDollars` for its capped `.progress` case but feeds an uncapped
            // `.values` row when there's no monthly cap.
            data.limit = nil
            // Optional expiry instants (Claude and Codex rate-limit resets): listed in the row's hover
            // popover, which formats them live against the clock.
            data.expiriesAt = expiriesAt
            data.hasData = !data.selectedValues.isEmpty
            return data
        case .badge(_, let text, _, let subtitle):
            var data = descriptor.sample
            data.valueTextOverride = text
            data.subtitleOverride = subtitle
            return data
        }
    }
}

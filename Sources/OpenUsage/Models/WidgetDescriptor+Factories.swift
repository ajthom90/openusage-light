import Foundation

/// Shared descriptor factories — the one place that knows how a descriptor's template `WidgetData`
/// is assembled, so providers declare flat metric lists instead of re-implementing the same private
/// builders. Template numbers are structural only (a row without real data renders the no-data marker,
/// never the template), so every factory seeds `used: 0`.
extension WidgetDescriptor {
    /// Bounded 0–100% meter (session/weekly-style quotas). `sessionStartSignal` opts the tile into the
    /// "Not started" fresh-window treatment (rolling 5-hour session pools) and names how that state is
    /// detected for this provider — see `WidgetData.SessionStartSignal`.
    static func percent(
        id: String,
        provider: Provider,
        title: String,
        metricLabel: String? = nil,
        sessionStartSignal: WidgetData.SessionStartSignal? = nil
    ) -> WidgetDescriptor {
        var sample = WidgetData(title: title, icon: provider.icon, kind: .percent, used: 0, limit: 100)
        sample.sessionStartSignal = sessionStartSignal
        return make(id: id, provider: provider, metricLabel: metricLabel ?? title, sample: sample)
    }

    /// Bounded dollar meter whose subtitle reads "$<limit> <limitNoun>" (noun defaults to "limit").
    /// `valueWord` is the trailing word for the *uncapped* fallback: a tile like Claude's Extra Usage is a
    /// meter when the provider reports a monthly cap (`.progress`) but an unbounded "$1.2K spent" row
    /// (`.values`) when it doesn't, and that row needs a word. It's inert for the bounded rendering.
    static func boundedDollars(
        id: String,
        provider: Provider,
        title: String,
        metricLabel: String? = nil,
        limit: Double,
        limitNoun: String? = nil,
        valueWord: String? = nil
    ) -> WidgetDescriptor {
        make(id: id, provider: provider, metricLabel: metricLabel ?? title,
             sample: WidgetData(title: title, icon: provider.icon,
                                kind: .dollars, used: 0, limit: limit, limitNoun: limitNoun,
                                unboundedValueWord: valueWord))
    }

    /// Bounded count meter (e.g. requests per billing cycle). `periodDurationMs` lets the subtitle
    /// show the cycle's reset cadence instead of the bare suffix.
    static func boundedCount(
        id: String,
        provider: Provider,
        title: String,
        metricLabel: String? = nil,
        limit: Double,
        suffix: String,
        periodDurationMs: Int? = nil
    ) -> WidgetDescriptor {
        make(id: id, provider: provider, metricLabel: metricLabel ?? title,
             sample: WidgetData(title: title, icon: provider.icon,
                                kind: .count, used: 0, limit: limit, countSuffix: suffix,
                                periodDurationMs: periodDurationMs))
    }

    /// Unbounded numeric row backed by a provider `.values` line.
    static func values(
        id: String,
        provider: Provider,
        title: String,
        metricLabel: String? = nil,
        selection: ValueSelection = .all,
        valueWord: String? = nil,
        traySuffix: String? = nil,
        showsResetExpiries: Bool = false
    ) -> WidgetDescriptor {
        // `kind` is unused for `.values` rendering (each value carries its own), but a count-only tile
        // reads tidier seeded as `.count`; everything else defaults to `.dollars`.
        let kind: MetricKind = { if case .kind(let only) = selection { return only }; return .dollars }()
        var sample = WidgetData(title: title, icon: provider.icon, kind: kind, used: 0, limit: nil,
                                unboundedValueWord: valueWord)
        sample.selection = selection
        sample.traySuffix = traySuffix
        sample.showsResetExpiries = showsResetExpiries
        return make(id: id, provider: provider, metricLabel: metricLabel ?? title, sample: sample)
    }

    /// Combined tile showing every value in a `.values` row.
    static func combined(
        id: String,
        provider: Provider,
        title: String,
        metricLabel: String? = nil
    ) -> WidgetDescriptor {
        values(id: id, provider: provider, title: title, metricLabel: metricLabel, selection: .all)
    }

    /// Unbounded dollar balance with a custom trailing word (e.g. "$1,503.00 left").
    static func dollarBalance(
        id: String,
        provider: Provider,
        title: String,
        metricLabel: String? = nil,
        valueWord: String
    ) -> WidgetDescriptor {
        make(id: id, provider: provider, metricLabel: metricLabel ?? title,
             sample: WidgetData(title: title, icon: provider.icon,
                                kind: .dollars, used: 0, limit: nil, unboundedValueWord: valueWord))
    }

    /// Unbounded count resolved from a provider `.badge` line via `valueTextOverride`
    /// (e.g. Grok pay-as-you-go).
    static func badge(
        id: String,
        provider: Provider,
        title: String,
        metricLabel: String? = nil
    ) -> WidgetDescriptor {
        make(id: id, provider: provider, metricLabel: metricLabel ?? title,
             sample: WidgetData(title: title, icon: provider.icon,
                                kind: .count, used: 0, limit: nil))
    }

    private static func make(
        id: String,
        provider: Provider,
        metricLabel: String,
        sample: WidgetData,
        pinnable: Bool = true
    ) -> WidgetDescriptor {
        WidgetDescriptor(
            id: id,
            providerID: provider.id,
            metricLabel: metricLabel,
            sample: sample,
            pinnable: pinnable
        )
    }
}

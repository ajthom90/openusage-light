import SwiftUI

/// The layouts a usage widget draws. WidgetKit's families map onto these in the widget extension.
public enum UsageWidgetFamily: Sendable {
    case small, medium, large, lockCircular, lockRectangular
}

/// The widget's content for each family, kept free of WidgetKit so the app can preview it and tests can
/// build it. The widget supplies the background.
public struct UsageWidgetView: View {
    let snapshot: UsageSnapshot
    let family: UsageWidgetFamily

    public init(snapshot: UsageSnapshot, family: UsageWidgetFamily) {
        self.snapshot = snapshot
        self.family = family
    }

    public var body: some View {
        switch family {
        case .small: AccountRows(accounts: Array(snapshot.accounts.prefix(4)), spacing: 9).topLeading()
        case .medium: MediumLayout(accounts: snapshot.accounts).topLeading()
        case .large: LargeLayout(snapshot: snapshot).topLeading()
        case .lockCircular: CircularGauge(accounts: snapshot.accounts)
        case .lockRectangular: AccountRows(accounts: Array(snapshot.accounts.prefix(2)), spacing: 4, compact: true).topLeading()
        }
    }
}

private extension View {
    /// Fills the widget and starts at its top-left, so a short list does not float in the middle.
    func topLeading() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Green-to-red the way the Mac dashboard warns: nothing until 70%, orange to 90%, then red.
func usageTint(_ fraction: Double) -> Color {
    fraction >= 0.9 ? .red : (fraction >= 0.7 ? .orange : .blue)
}

private struct AccountRows: View {
    let accounts: [MobileAccount]
    let spacing: CGFloat
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(accounts) { account in
                if let meter = account.headline { MeterLine(title: account.providerName, meter: meter, compact: compact) }
            }
        }
    }
}

private struct MeterLine: View {
    let title: String
    let meter: MobileMeter
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold)).lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                Text(meter.shortText).font(compact ? .caption2 : .caption).foregroundStyle(.secondary).monospacedDigit()
            }
            if let fraction = meter.fraction {
                ProgressView(value: fraction).tint(usageTint(meter.usedFraction ?? fraction))
            }
        }
    }

}

private struct MediumLayout: View {
    let accounts: [MobileAccount]

    var body: some View {
        let shown = Array(accounts.prefix(6))
        // One column up to three accounts; beyond that two, filled down the left first.
        let half = shown.count <= 3 ? shown.count : (shown.count + 1) / 2
        HStack(alignment: .top, spacing: 16) {
            AccountRows(accounts: Array(shown.prefix(half)), spacing: 8)
            if shown.count > half { AccountRows(accounts: Array(shown.dropFirst(half)), spacing: 8) }
        }
    }
}

private struct LargeLayout: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(snapshot.accounts.prefix(5)) { account in
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.providerName).font(.caption.weight(.bold))
                    ForEach(account.meters.filter { $0.fraction != nil }.prefix(2)) { meter in
                        MeterLine(title: meter.title, meter: meter)
                    }
                    if account.meters.allSatisfy({ $0.fraction == nil }), let first = account.meters.first {
                        MeterLine(title: first.title, meter: first)
                    }
                }
            }
            Spacer(minLength: 0)
            Text("Updated \(snapshot.generatedAt.formatted(.relative(presentation: .named)))")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct CircularGauge: View {
    let accounts: [MobileAccount]

    var body: some View {
        // The most-used headline meter: the one closest to its limit.
        let top = accounts.compactMap(\.headline).filter { $0.fraction != nil }
            .max { ($0.usedFraction ?? 0) < ($1.usedFraction ?? 0) }
        Gauge(value: top?.fraction ?? 0) {
            Text("Use")
        } currentValueLabel: {
            Text(top?.fraction.map { "\(Int(($0 * 100).rounded()))" } ?? "–")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }
}

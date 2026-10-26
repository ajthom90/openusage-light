import SwiftUI

/// The 5 pt capacity bar on a dashboard row, filled with what is left (or what is used, under the Used
/// setting) in the severity's colour: blue well within limits, orange when projected to land inside the
/// last 10%, red when projected to run out (`Theme.severityColor`). The track is the system's quaternary
/// fill. Any non-zero fill draws at least a full circle, so 1–2% never squashes into a sliver.
struct UsageMeterBar: View {
    /// The share shown, 0...1.
    let fill: Double
    let severity: WidgetData.MeterSeverity

    /// Party easter egg: fill the bar with the party gradient instead of the severity color.
    @Environment(\.popoverPartyMode) private var partyMode

    static let height = DashboardGrid.barHeight

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(partyMode ? PartyMode.meterFill : AnyShapeStyle(Theme.severityColor(severity)))
                    .frame(width: fillWidth(track: proxy.size.width))
            }
        }
        .frame(height: Self.height)
        .animation(Motion.spring, value: fill)
        .accessibilityHidden(true)
    }

    private func fillWidth(track: CGFloat) -> CGFloat {
        guard fill > 0 else { return 0 }
        return max(Self.height, track * min(fill, 1))
    }
}

import SwiftUI

/// The capsule meter shared by the dashboard lines and the share card rows. The fill is a flat system
/// color carrying the pace verdict (blue = well within limits, orange = projected to land inside the
/// last 10%, red = projected to run out; `Theme.severityColor` / `MeterState.severity`). Empty and
/// colorless without data. A thin tick marks the even-pace line on orange and red bars, and on blue
/// when "always show pacing" is on; it rides in an overlay so it pokes out top and bottom without
/// changing the bar's height.
struct UsageMeterBar: View {
    let data: WidgetData
    let state: WidgetData.MeterState

    /// Party easter egg: fill the bar with the party gradient instead of the severity color.
    @Environment(\.popoverPartyMode) private var partyMode

    /// A thin 5 pt capsule, as in the card dashboard Robin chose.
    static let height: CGFloat = 5
    private static let paceTickWidth: CGFloat = 2
    private static let paceTickOverhang: CGFloat = 4

    var body: some View {
        let tick = data.paceTick(for: state)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(partyMode ? PartyMode.meterFill : fill)
                    .frame(width: fillWidth(track: proxy.size.width))
            }
            .overlay(alignment: .leading) {
                if let tick {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: Self.paceTickWidth, height: Self.height + Self.paceTickOverhang)
                        .offset(x: paceTickOffset(track: proxy.size.width, fraction: tick))
                }
            }
        }
        .frame(height: Self.height)
        .animation(Motion.spring, value: data.fraction)
        .accessibilityHidden(true)
    }

    private var fill: AnyShapeStyle {
        state.severity.map { AnyShapeStyle(Theme.severityColor($0)) } ?? AnyShapeStyle(Color.secondary)
    }

    /// Centers the tick on its fraction, clamped so it never pokes past either rounded end.
    private func paceTickOffset(track: CGFloat, fraction: Double) -> CGFloat {
        let centered = track * fraction - Self.paceTickWidth / 2
        return min(max(centered, 0), max(track - Self.paceTickWidth, 0))
    }

    /// Any non-zero fraction renders at least a full circle, so 1–2% never squashes into a sliver.
    private func fillWidth(track: CGFloat) -> CGFloat {
        guard data.hasData, data.fraction > 0 else { return 0 }
        return max(Self.height, track * data.fraction)
    }
}

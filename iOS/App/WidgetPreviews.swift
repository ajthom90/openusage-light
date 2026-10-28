import OpenUsageMobile
import SwiftUI

/// Every widget layout at its on-screen size, so they can be checked from a screenshot.
struct WidgetPreviews: View {
    private let snapshot = UsageSnapshot.sample()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                card(.small, 158, 158)
                card(.medium, 338, 158)
                card(.large, 338, 354)
                HStack(spacing: 16) {
                    card(.lockCircular, 76, 76).foregroundStyle(.white).background(.black, in: .circle)
                    card(.lockRectangular, 172, 76).foregroundStyle(.white).background(.black, in: .rect(cornerRadius: 12))
                }
            }
            .padding()
        }
    }

    private func card(_ family: UsageWidgetFamily, _ width: CGFloat, _ height: CGFloat) -> some View {
        UsageWidgetView(snapshot: snapshot, family: family)
            .padding(family == .lockCircular || family == .lockRectangular ? 6 : 16)
            .frame(width: width, height: height)
            .background(.fill.tertiary, in: .rect(cornerRadius: family == .lockCircular ? 38 : 22))
    }
}

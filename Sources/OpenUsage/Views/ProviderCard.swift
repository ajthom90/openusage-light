import SwiftUI

/// The share card's grouped metric-card body: a spacing-0 stack of rows (separated by row padding,
/// never dividers), a gutter that keeps the first/last row off the card edge, and the shared card
/// surface.
struct DashboardMetricCard<Rows: View>: View {
    @ViewBuilder var rows: Rows

    var body: some View {
        VStack(spacing: 0) {
            rows
        }
        .padding(.vertical, 5)
        .cardSurface()
    }
}

import SwiftUI

/// The phone and tablet dashboard: one card per account, in the order saved on the Mac. The cards flow into
/// as many columns as the width the app is given allows (one on a phone, more on an iPad or an unfolded
/// iPhone Duo), so the layout follows the space, never the device.
public struct DashboardScreen: View {
    let model: MobileModel

    public init(model: MobileModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let grid = GridMetrics(width: proxy.size.width, foldWidth: foldWidth(in: proxy))
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let message = model.message {
                            Banner(text: message, systemImage: "info.circle", tint: .secondary)
                        }
                        if model.isOutdated(), model.source != .sample {
                            Banner(
                                text: "Your Mac hasn't updated this in a while. It may be asleep or offline.",
                                systemImage: "clock.badge.exclamationmark", tint: .orange
                            )
                        }
                        MasonryLayout(columns: grid.columns, columnGap: grid.gap, rowSpacing: 16) {
                            ForEach(model.accounts) { AccountCard(account: $0) }
                        }
                        if let updated = model.generatedAt {
                            Text(footer(updated)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: 1100)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(pageBackground)
            .navigationTitle("Usage")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Picker("Show Usage As", selection: Binding(get: { model.choice }, set: { model.setChoice($0) })) {
                            ForEach(DisplayChoice.allCases) { Text($0.label).tag($0) }
                        }
                    } label: {
                        Label("Show Usage As", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
        }
    }

    /// The width of the fold when iPhone Duo is partially open (a vertical hinge splitting the display into
    /// two halves), else 0. Cards are kept out of it by making it the gap between the two columns.
    private func foldWidth(in proxy: GeometryProxy) -> CGFloat {
        #if canImport(UIKit)
        if #available(iOS 27.1, *) {
            let folds = proxy.reservedRegions(kind: .division).filter { $0.isActive && $0.frame.height > $0.frame.width }
            return folds.map(\.frame.width).max() ?? 0
        }
        #endif
        return 0
    }

    private func footer(_ updated: Date) -> String {
        let when = updated.formatted(.relative(presentation: .named))
        return model.source == .sample ? "Example numbers" : "Updated by your Mac \(when)"
    }
}

/// How many columns, and how wide a gap between them, for a given width. Always an even number of columns
/// beyond one, so the content divides cleanly down the middle when a Duo is folded.
struct GridMetrics: Equatable {
    let columns: Int
    let gap: CGFloat

    init(width: CGFloat, foldWidth: CGFloat) {
        if foldWidth > 0 {
            columns = 2
            gap = foldWidth
        } else {
            columns = width < 640 ? 1 : (width < 1200 ? 2 : 4)
            gap = 16
        }
    }
}

private var pageBackground: Color {
    #if canImport(UIKit)
    Color(.systemGroupedBackground)
    #else
    Color.clear
    #endif
}

private var cardBackground: Color {
    #if canImport(UIKit)
    Color(.secondarySystemGroupedBackground)
    #else
    Color.gray.opacity(0.1)
    #endif
}

private struct Banner: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(tint)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground, in: .rect(cornerRadius: 12))
    }
}

private struct AccountCard: View {
    let account: MobileAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 8)
            if let notice = account.notice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.orange)
                    .padding(.bottom, 8)
            }
            ForEach(Array(account.meters.enumerated()), id: \.element.id) { index, meter in
                if index > 0 { Divider().padding(.vertical, 8) }
                MeterRow(meter: meter)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: .rect(cornerRadius: 16))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(account.providerName).font(.headline)
            if !account.name.isEmpty { Text(account.name).foregroundStyle(.secondary) }
            Spacer()
            if let plan = account.plan { Text(plan).font(.caption).foregroundStyle(.secondary) }
            if account.isStale {
                Label("Outdated", systemImage: "clock.badge.exclamationmark").font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

private struct MeterRow: View {
    let meter: MobileMeter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(meter.title)
                Spacer()
                Text(meter.valueText).foregroundStyle(.secondary)
            }
            if let fraction = meter.fraction {
                ProgressView(value: fraction).tint(usageTint(meter.usedFraction ?? fraction))
            }
            if let resetsAt = meter.resetsAt {
                Text("Resets \(resetsAt.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

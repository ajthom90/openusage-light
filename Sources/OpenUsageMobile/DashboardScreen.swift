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
                content(in: proxy)
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

    @ViewBuilder
    private func content(in proxy: GeometryProxy) -> some View {
        let fold = FoldGeometry(regions: foldRegions(in: proxy))
        let heights = model.accounts.map(PaneSplit.estimatedHeight(of:))
        let bannerRoom: CGFloat = (model.message != nil || model.isOutdated()) ? 60 : 0
        switch fold {
        case .horizontal(let minY, let maxY):
            // A fold across the middle: one pane above it and one below, each scrolling on its own, with the
            // hinge itself left empty so no card is hidden under it.
            let columns = GridMetrics(width: proxy.size.width).columns
            let above = PaneSplit.countAbove(heights: heights, columns: columns, spacing: 16, available: minY - 32 - bannerRoom)
            VStack(spacing: 0) {
                ScrollView { pane(Array(model.accounts.prefix(above)), columns: columns, showsBanners: true, showsFooter: false) }
                    .frame(height: max(minY, 0))
                Color.clear.frame(height: max(maxY - minY, 0))
                ScrollView { pane(Array(model.accounts.dropFirst(above)), columns: columns, showsBanners: false, showsFooter: true) }
                    .frame(maxHeight: .infinity)
            }
        case .vertical(let minX, let maxX):
            // A fold down the middle: one pane on each side of the hinge's real position, the cards shared out
            // so the two sides come out about equally tall.
            let (left, right) = PaneSplit.sides(heights: heights, spacing: 16)
            HStack(spacing: 0) {
                ScrollView { pane(left.map { model.accounts[$0] }, columns: 1, showsBanners: true, showsFooter: false) }
                    .frame(width: max(minX, 0))
                Color.clear.frame(width: max(maxX - minX, 0))
                ScrollView { pane(right.map { model.accounts[$0] }, columns: 1, showsBanners: false, showsFooter: true) }
                    .frame(maxWidth: .infinity)
            }
        case .none:
            ScrollView { pane(model.accounts, columns: GridMetrics(width: proxy.size.width).columns, showsBanners: true, showsFooter: true) }
        }
    }

    private func pane(_ accounts: [MobileAccount], columns: Int, showsBanners: Bool, showsFooter: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsBanners {
                if let message = model.message {
                    Banner(text: message, systemImage: "info.circle", tint: .secondary)
                }
                if model.isOutdated(), model.source != .sample {
                    Banner(
                        text: "Your Mac hasn't updated this in a while. It may be asleep or offline.",
                        systemImage: "clock.badge.exclamationmark", tint: .orange
                    )
                }
            }
            MasonryLayout(columns: columns, columnGap: 16, rowSpacing: 16) {
                ForEach(accounts) { AccountCard(account: $0) }
            }
            if showsFooter, let updated = model.generatedAt {
                Text(footer(updated)).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: 1100)
        .frame(maxWidth: .infinity)
    }

    /// The active folds the system reports (iPhone Duo, iOS 27.1 and later), as plain frames.
    private func foldRegions(in proxy: GeometryProxy) -> [CGRect] {
        #if canImport(UIKit)
        if #available(iOS 27.1, *) {
            return proxy.reservedRegions(kind: .division).filter(\.isActive).map(\.frame)
        }
        #endif
        return []
    }

    private func footer(_ updated: Date) -> String {
        let when = updated.formatted(.relative(presentation: .named))
        return model.source == .sample ? "Example numbers" : "Updated by your Mac \(when)"
    }
}

/// Where the fold is, if the device is partially open: a vertical hinge splits the display left and right, a
/// horizontal one top and bottom.
enum FoldGeometry: Equatable {
    case none
    case vertical(minX: CGFloat, maxX: CGFloat)
    case horizontal(minY: CGFloat, maxY: CGFloat)

    init(regions: [CGRect]) {
        // The tallest-or-widest band wins if the system ever reports more than one.
        if let band = regions.filter({ $0.width > 0 && $0.height > 0 }).max(by: { max($0.width, $0.height) < max($1.width, $1.height) }) {
            self = band.height > band.width ? .vertical(minX: band.minX, maxX: band.maxX) : .horizontal(minY: band.minY, maxY: band.maxY)
        } else {
            self = .none
        }
    }
}

/// Which accounts go above a horizontal fold and which below, in the saved order: as many from the start as
/// fit in the space above the fold (always at least one), the rest below.
enum PaneSplit {
    /// A card's height before it is measured: its header plus about this much per meter.
    static func estimatedHeight(of account: MobileAccount) -> CGFloat {
        45 + 58 * CGFloat(max(account.meters.count, 1)) + (account.notice == nil ? 0 : 24)
    }

    /// Which cards go on the left of a vertical fold and which on the right (indexes, each in saved order),
    /// sharing them out so the two sides come out about equally tall.
    static func sides(heights: [CGFloat], spacing: CGFloat) -> (left: [Int], right: [Int]) {
        let slots = MasonryPlacement.place(heights: heights, columns: 2, spacing: spacing).slots
        let indexes = Array(slots.indices)
        return (indexes.filter { slots[$0].column == 0 }, indexes.filter { slots[$0].column == 1 })
    }

    /// How many leading cards fit above the fold when packed into `columns` columns.
    static func countAbove(heights: [CGFloat], columns: Int, spacing: CGFloat, available: CGFloat) -> Int {
        var count = 0
        for next in 1...max(heights.count, 1) where next <= heights.count {
            let height = MasonryPlacement.place(heights: Array(heights.prefix(next)), columns: columns, spacing: spacing).height
            if height > available, count > 0 { break }
            count = next
            if height > available { break }
        }
        return count
    }
}

/// How many columns for a given width: always an even number beyond one, so content divides cleanly.
struct GridMetrics: Equatable {
    let columns: Int

    init(width: CGFloat) {
        columns = width < 640 ? 1 : (width < 1200 ? 2 : 4)
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

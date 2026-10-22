import SwiftUI
import XCTest
@testable import OpenUsage

@MainActor
final class ProviderHeaderLayoutTests: XCTestCase {
    private let longPlan = String(repeating: "Future Enterprise Entitlement ", count: 12)
    private let codexProvider = Provider(id: "codex", displayName: "Codex", icon: .providerMark("codex"))
    private let claudeProvider = Provider(id: "claude@1", displayName: "Claude", icon: .providerMark("claude"), accountLabel: "Personal")
    /// The grouped box: the 320 pt popover minus its margin on each side. An account pads itself.
    private let boxWidth = 320 - 2 * PanelMetrics.margin

    func testDashboardAccountFitsOversizedPlan() throws {
        let section = DashboardAccountSection(
            account: DashboardAccount(provider: codexProvider, lines: []),
            plan: longPlan,
            notice: "Refresh failed"
        ) { _ in EmptyView() }

        try assertFits(section, width: boxWidth)
    }

    /// A Codex account once lost its Weekly bar: name, plan, and metric shared one line, and the bar was
    /// dropped first when the line ran out of room. The name line now stands over every metric line.
    func testAccountDrawsItsBarBesideALongNameAndPlan() throws {
        let weekly = WidgetData(title: "Weekly", icon: .providerMark("codex"), kind: .percent, used: 40, limit: 100)
        var credits = WidgetData(title: "Credits", icon: .providerMark("codex"), kind: .count, used: 452, limit: nil)
        credits.values = [MetricValue(number: 452, kind: .count, label: "credits")]
        let provider = Provider(id: "codex@1", displayName: "Codex", icon: .providerMark("codex"), accountLabel: "Sunstory Engineering")
        let section = DashboardAccountSection(
            account: DashboardAccount(provider: provider, lines: [line(weekly), line(credits)]),
            plan: longPlan,
            notice: "Refresh failed"
        ) { DashboardMetricLine(data: $0.data, labelWidth: DashboardMetricLine.labelWidth(for: ["Weekly", "Credits"])) }

        let bitmap = try Bitmap(section, width: boxWidth)
        let row = Int(DashboardMetricLine.height)
        XCTAssertEqual(bitmap.height, 3 * row, "a name line and one line per metric")
        // The meter's blue fill is the only saturated color on the Weekly line, rows `row..<2 * row`.
        let saturated = (row..<2 * row).reduce(0) { count, y in
            count + (0..<bitmap.width).filter { x in
                let (r, g, b, a) = bitmap[x, y]
                return b > 180 && b - r > 120 && a > 200 && g < 200
            }.count
        }
        XCTAssertGreaterThan(saturated, 60, "the Weekly bar's fill")
    }

    /// The provider's mark, the account names, and the metric labels start at one x, as in a grouped
    /// form. A disclosure triangle once pushed the names and labels 12 pt right of the mark.
    func testMarkNameAndLabelsShareOneLeadingEdge() throws {
        let weekly = WidgetData(title: "Weekly", icon: .providerMark("claude"), kind: .percent, used: 24, limit: 100)
        let session = WidgetData(title: "Session", icon: .providerMark("claude"), kind: .percent, used: 30, limit: 100)
        let account = DashboardAccount(provider: claudeProvider, lines: [line(session), line(weekly)])
        let card = DashboardProviderCard(family: DashboardFamily(id: "claude", provider: claudeProvider, accounts: [account])) {
            DashboardAccountSection(account: $0, plan: "Max 5x") {
                DashboardMetricLine(data: $0.data, labelWidth: DashboardMetricLine.labelWidth(for: ["Session", "Weekly"]))
            }
        }

        let edges = try Bitmap(card, width: boxWidth, scale: 2).inkBands().map(\.first)
        XCTAssertEqual(edges.count, 4, "the section header, the name line, and two metric lines")
        let spread = (edges.max() ?? 0) - (edges.min() ?? 0)
        XCTAssertLessThanOrEqual(spread, 1.5, "leading edges \(edges)")
        XCTAssertEqual(edges.min() ?? 0, DashboardBox.textInset, accuracy: 1.5)
    }

    func testThePlanFollowsTheName() throws {
        func nameLine(plan: String?) throws -> Bitmap.Band {
            let section = DashboardAccountSection(account: DashboardAccount(provider: claudeProvider, lines: []), plan: plan) { _ in EmptyView() }
            return try XCTUnwrap(Bitmap(section, width: boxWidth, scale: 2).inkBands().first)
        }
        let bare = try nameLine(plan: nil)
        let planned = try nameLine(plan: "Max 5x")
        XCTAssertEqual(planned.first, bare.first)
        XCTAssertGreaterThan(planned.last, bare.last + 20, "the plan draws after the name")
    }

    func testShareHeaderFitsOversizedPlan() throws {
        let card = ShareCardView(
            provider: codexProvider, plan: longPlan, rows: [], appearance: .light
        )
        // Test the header itself: the card's outer fixed frame would hide child overflow.
        try assertFits(card.headerRow, width: ShareCardView.width - 32)
    }

    private func line(_ data: WidgetData) -> DashboardLine {
        DashboardLine(descriptor: WidgetDescriptor(id: data.title, providerID: "p", metricLabel: data.title, sample: data), data: data)
    }

    private func assertFits<Content: View>(
        _ content: Content, width: CGFloat, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let bitmap = try Bitmap(content, width: width)
        XCTAssertLessThanOrEqual(bitmap.width, Int(width), file: file, line: line)
        XCTAssertGreaterThan(bitmap.height, 0, file: file, line: line)
    }
}

/// A view rendered offscreen in light mode, as RGBA pixels with the top row first.
private struct Bitmap {
    struct Band {
        /// The x of the band's first and last ink, in points.
        let first: CGFloat
        let last: CGFloat
    }

    let width: Int
    let height: Int
    let scale: CGFloat
    private var pixels: [UInt8]

    @MainActor
    init(_ content: some View, width: CGFloat, scale: CGFloat = 1) throws {
        let renderer = ImageRenderer(content: content
            .environment(\.hoverTooltipsDisabled, true)
            .environment(\.colorScheme, .light))
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.cgImage)
        self.width = image.width
        self.height = image.height
        self.scale = scale
        pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        XCTAssertTrue(drawn)
    }

    subscript(x: Int, y: Int) -> (Int, Int, Int, Int) {
        let i = (y * width + x) * 4
        return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]), Int(pixels[i + 3]))
    }

    /// Each horizontal band of ink, top to bottom: a line of text, or the provider's mark. Ink is a pixel
    /// that differs clearly from its row's background, sampled 6 pt in from the leading edge. The 6 pt at
    /// either side hold only a grouped box's rounded edge, and so do bands under 4 pt tall, so neither
    /// counts.
    func inkBands() -> [Band] {
        let background = Int(6 * scale)
        func isInk(_ x: Int, _ y: Int) -> Bool {
            let (p, q) = (self[x, y], self[background, y])
            return max(abs(p.0 - q.0), abs(p.1 - q.1), abs(p.2 - q.2), abs(p.3 - q.3)) > 40
        }
        var bands: [Band] = []
        var top: Int?
        var first = Int.max, last = Int.min
        for y in 0...height {
            let ink = y < height ? (background..<(width - background)).filter { isInk($0, y) } : []
            if let x = ink.first, let end = ink.last {
                top = top ?? y
                first = min(first, x)
                last = max(last, end)
            } else if let start = top {
                if CGFloat(y - start) >= 4 * scale {
                    bands.append(Band(first: CGFloat(first) / scale, last: CGFloat(last + 1) / scale))
                }
                top = nil
                first = .max
                last = .min
            }
        }
        return bands
    }
}

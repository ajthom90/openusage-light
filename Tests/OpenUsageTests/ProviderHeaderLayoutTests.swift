import SwiftUI
import XCTest
@testable import OpenUsage

@MainActor
final class ProviderHeaderLayoutTests: XCTestCase {
    private let longPlan = String(repeating: "Future Enterprise Entitlement ", count: 12)
    private let codexProvider = Provider(id: "codex", displayName: "Codex", icon: .providerMark("codex"))

    func testExpandedDashboardAccountFitsOversizedPlan() throws {
        let account = DashboardAccount(provider: codexProvider, lines: [])
        let section = DashboardAccountSection(
            account: account,
            plan: longPlan,
            notice: "Refresh failed",
            isExpanded: true
        ) { _ in EmptyView() }
        .environment(\.hoverTooltipsDisabled, true)

        // The grouped box: the 320pt popover minus its margin on each side. The block pads itself.
        try assertFits(section, width: 320 - 2 * PanelMetrics.margin)
    }

    /// A collapsed Codex account once lost its Weekly bar: name, plan, and metric shared one line, and
    /// the bar was dropped first when the line ran out of room. Each summary metric now has its own line.
    func testCollapsedAccountDrawsItsBarBesideALongNameAndPlan() throws {
        let weekly = WidgetData(title: "Weekly", icon: .providerMark("codex"), kind: .percent, used: 40, limit: 100)
        var credits = WidgetData(title: "Credits", icon: .providerMark("codex"), kind: .count, used: 452, limit: nil)
        credits.values = [MetricValue(number: 452, kind: .count, label: "credits")]
        let lines = [weekly, credits].map {
            DashboardLine(descriptor: WidgetDescriptor(id: $0.title, providerID: "codex", metricLabel: $0.title, sample: $0), data: $0)
        }
        let provider = Provider(id: "codex@1", displayName: "Codex", icon: .providerMark("codex"), accountLabel: "Sunstory Engineering")
        let section = DashboardAccountSection(
            account: DashboardAccount(provider: provider, lines: lines),
            plan: longPlan,
            notice: "Refresh failed",
            isExpanded: false
        ) { DashboardMetricLine(data: $0.data, labelWidth: DashboardMetricLine.labelWidth(for: ["Weekly", "Credits"])) }
        .environment(\.hoverTooltipsDisabled, true)
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: section)
        renderer.proposedSize = ProposedViewSize(width: 320 - 2 * PanelMetrics.margin, height: nil)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let row = Int(DashboardMetricLine.height)
        XCTAssertEqual(image.height, 2 * row, "a header line and one summary line")

        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // The meter's blue fill is the only saturated color on the summary line (the bitmap's rows run
        // top-down here, so the summary line is rows `row..<2 * row`).
        let saturated = (row..<height).reduce(0) { count, y in
            count + (0..<width).filter { x in
                let i = (y * width + x) * 4
                let (r, g, b) = (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
                return b > 180 && b - r > 120 && pixels[i + 3] > 200 && g < 200
            }.count
        }
        XCTAssertGreaterThan(saturated, 60, "the Weekly bar's fill")
    }

    func testShareHeaderFitsOversizedPlan() throws {
        let card = ShareCardView(
            provider: codexProvider, plan: longPlan, rows: [], appearance: .light
        )
        // Test the header itself: the card's outer fixed frame would hide child overflow.
        try assertFits(card.headerRow, width: ShareCardView.width - 32)
    }

    private func assertFits<Content: View>(
        _ content: Content, width: CGFloat, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage, file: file, line: line)
        XCTAssertLessThanOrEqual(image.width, Int(width), file: file, line: line)
        XCTAssertGreaterThan(image.height, 0, file: file, line: line)
    }
}

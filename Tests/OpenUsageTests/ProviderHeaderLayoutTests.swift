import SwiftUI
import XCTest
@testable import OpenUsage

@MainActor
final class ProviderHeaderLayoutTests: XCTestCase {
    private let longPlan = String(repeating: "Future Enterprise Entitlement ", count: 12)
    private let codexProvider = Provider(id: "codex", displayName: "Codex", icon: .providerMark("codex"))
    private let claudeProvider = Provider(id: "claude@1", displayName: "Claude", icon: .providerMark("claude"), accountLabel: "Personal")
    /// The card: the panel minus its margin on each side. An account pads itself.
    private let boxWidth = PanelMetrics.width - 2 * PanelMetrics.margin

    func testDashboardAccountFitsOversizedPlan() throws {
        let section = DashboardAccountSection(
            account: DashboardAccount(provider: codexProvider, lines: []),
            badges: AccountBadges(plan: longPlan, notice: "Refresh failed")
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
            badges: AccountBadges(plan: longPlan, notice: "Refresh failed")
        ) { DashboardMetricLine(data: $0.data) }

        let bitmap = try Bitmap(section, width: boxWidth)
        let padding = Int(DashboardBox.accountPadding)
        let nameLine = Int(DashboardAccountSection<EmptyView>.lineHeight)
        let row = Int(DashboardMetricLine.height)
        XCTAssertEqual(bitmap.height, 2 * padding + nameLine + 2 * row, "a name line and one line per metric")
        // The meter's blue fill is the only saturated color on the Weekly line.
        let weeklyTop = padding + nameLine
        let saturated = (weeklyTop..<weeklyTop + row).reduce(0) { count, y in
            count + (0..<bitmap.width).filter { x in
                let (r, g, b, a) = bitmap[x, y]
                return b > 180 && b - r > 120 && a > 200 && g < 200
            }.count
        }
        XCTAssertGreaterThan(saturated, 60, "the Weekly bar's fill")
    }

    /// The provider's mark, the account names, and the metric labels start at one x inside the card. A
    /// disclosure triangle once pushed the names and labels 12 pt right of the mark.
    func testMarkNameAndLabelsShareOneLeadingEdge() throws {
        let edges = try Bitmap(twoAccountCard(), width: boxWidth, scale: 2).inkBands().map(\.first)
        XCTAssertEqual(edges.count, 7, "the card header, then a name line and two metric lines per account")
        let spread = (edges.max() ?? 0) - (edges.min() ?? 0)
        XCTAssertLessThanOrEqual(spread, 1.5, "leading edges \(edges)")
        XCTAssertEqual(edges.min() ?? 0, DashboardBox.inset, accuracy: 1.5)
    }

    /// With two accounts nothing moves into the header: it is the mark and the provider's name alone,
    /// and each account keeps its name line with its plan tag at the trailing edge.
    func testATwoAccountCardKeepsEachAccountsNameLine() throws {
        let bands = try Bitmap(twoAccountCard(), width: boxWidth, scale: 2).inkBands()
        XCTAssertEqual(bands.count, 7)
        XCTAssertLessThan(bands[0].last, boxWidth / 2, "the header holds a tag")
        for nameLine in [bands[1], bands[4]] {
            XCTAssertEqual(nameLine.last, boxWidth - DashboardBox.inset - 7, accuracy: 1.5, "an account's plan tag")
        }
    }

    /// With one account its plan tag moves to the trailing edge of the card's header and the account's
    /// name line goes away: metrics follow the header straight away.
    func testAOneAccountCardPutsThePlanTagInTheHeader() throws {
        let account = DashboardAccount(provider: claudeProvider, lines: [line(session), line(weekly)])
        let card = DashboardProviderCard(
            family: DashboardFamily(id: "claude", provider: claudeProvider, accounts: [account]),
            badges: { _ in AccountBadges(plan: "Max 5x") }
        ) {
            DashboardAccountSection(account: $0, showsAccountLine: false) { DashboardMetricLine(data: $0.data) }
        }

        let bands = try Bitmap(card, width: boxWidth, scale: 2).inkBands()
        XCTAssertEqual(bands.count, 3, "the card header and two metric lines, with no name line")
        XCTAssertEqual(bands[0].first, DashboardBox.inset, accuracy: 1.5)
        XCTAssertEqual(bands[0].last, boxWidth - DashboardBox.inset - 7, accuracy: 1.5, "the plan tag ends one inset from the card's edge")
    }

    /// Robin, on the roomier cards: "Everything takes too much space." Then, on shorter rows: "It's more
    /// about all the other padding." The rows keep their full height and the card's padding is small,
    /// so its heights are pinned in literal points, and changing any vertical step fails here: 10 above
    /// the header, 6 from the header to the first row, 24 per name line, 20 per metric line, 10 between
    /// two accounts and 10 below the last row. These cards were 191 and 90 pt, then 163 and 78.
    func testCardsKeepFullRowsAndTightPadding() throws {
        let sole = DashboardAccount(provider: claudeProvider, lines: [line(session), line(weekly)])
        let oneAccountCard = DashboardProviderCard(
            family: DashboardFamily(id: "claude", provider: claudeProvider, accounts: [sole]),
            badges: { _ in AccountBadges(plan: "Max 5x") }
        ) {
            DashboardAccountSection(account: $0, showsAccountLine: false) { DashboardMetricLine(data: $0.data) }
        }
        XCTAssertEqual(try Bitmap(twoAccountCard(), width: boxWidth).height, 181, "a card with two accounts of two metrics")
        XCTAssertEqual(try Bitmap(oneAccountCard, width: boxWidth).height, 84, "a card with one account of two metrics")
        XCTAssertEqual(DashboardBox.inset, 12, "the card's side padding")
        XCTAssertEqual(DashboardBox.cardSpacing, 8, "the gap between two cards")
    }

    /// The plan is a tag at the trailing edge of the account line, as in Robin's screenshot, not text
    /// after the name.
    func testThePlanTagSitsAtTheTrailingEdge() throws {
        func nameLine(plan: String?) throws -> Bitmap.Band {
            let section = DashboardAccountSection(
                account: DashboardAccount(provider: claudeProvider, lines: []), badges: AccountBadges(plan: plan)
            ) { _ in EmptyView() }
            return try XCTUnwrap(Bitmap(section, width: boxWidth, scale: 2).inkBands().first)
        }
        let bare = try nameLine(plan: nil)
        let planned = try nameLine(plan: "Max 5x")
        XCTAssertEqual(planned.first, bare.first)
        // The capsule's faint fill isn't ink; its text ends 7 pt inside it.
        XCTAssertEqual(planned.last, boxWidth - DashboardBox.inset - 7, accuracy: 1.5, "the tag ends one inset from the card's edge")
    }

    func testShareHeaderFitsOversizedPlan() throws {
        let card = ShareCardView(
            provider: codexProvider, plan: longPlan, rows: [], appearance: .light
        )
        // Test the header itself: the card's outer fixed frame would hide child overflow.
        try assertFits(card.headerRow, width: ShareCardView.width - 32)
    }

    /// A one-account header shows the account's name where a card with more accounts shows the
    /// provider's. Drawn in the same place and font, an account named "Claude" spans the provider's
    /// header exactly, and a longer custom name runs further.
    func testAOneAccountCardsHeaderShowsTheAccountsName() throws {
        func header(_ accounts: [Provider]) throws -> Bitmap.Band {
            let card = DashboardProviderCard(
                family: DashboardFamily(id: "claude", provider: accounts[0], accounts: accounts.map { DashboardAccount(provider: $0, lines: []) })
            ) { _ in EmptyView() }
            return try XCTUnwrap(Bitmap(card.header, width: boxWidth, scale: 2).inkBands().first)
        }
        func account(_ label: String, _ id: String = "claude@1") -> Provider {
            Provider(id: id, displayName: "Claude", icon: .providerMark("claude"), accountLabel: label)
        }
        let providerHeader = try header([account("Attention Machine"), account("Home", "claude@2")])
        let namedClaude = try header([account("Claude")])
        XCTAssertEqual(namedClaude.first, providerHeader.first, accuracy: 0.5)
        XCTAssertEqual(namedClaude.last, providerHeader.last, accuracy: 0.5, "the name isn't drawn where the provider's is")
        XCTAssertGreaterThan(try header([account("Attention Machine")]).last, providerHeader.last + 40, "the header shows the provider's name")
    }

    private let weekly = WidgetData(title: "Weekly", icon: .providerMark("claude"), kind: .percent, used: 24, limit: 100)
    private let session = WidgetData(title: "Session", icon: .providerMark("claude"), kind: .percent, used: 30, limit: 100)

    private func twoAccountCard() -> some View {
        let work = Provider(id: "claude@2", displayName: "Claude", icon: .providerMark("claude"), accountLabel: "Work")
        let accounts = [claudeProvider, work].map { DashboardAccount(provider: $0, lines: [line(session), line(weekly)]) }
        return DashboardProviderCard(
            family: DashboardFamily(id: "claude", provider: claudeProvider, accounts: accounts),
            badges: { _ in AccountBadges(plan: "Max 5x") }
        ) {
            DashboardAccountSection(account: $0, badges: AccountBadges(plan: "Max 5x")) { DashboardMetricLine(data: $0.data) }
        }
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

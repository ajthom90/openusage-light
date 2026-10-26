import SwiftUI
import XCTest
@testable import OpenUsage

/// The provider's header and card, as drawn: the plan sits 8 pt before the logo and is never cut, a long
/// name is; the header's text, every caption and every label start 12 pt in, and the logo ends where
/// the bars do; the heights are literal points; a hovered row keeps its height and fits its text.
@MainActor
final class ProviderHeaderLayoutTests: XCTestCase {
    /// The card: the panel minus its margin on each side.
    private let boxWidth = PanelMetrics.width - 2 * PanelMetrics.margin
    private let inset = DashboardGrid.cardPadding + DashboardGrid.inset

    private func claude(_ label: String?, _ id: String = "claude@1") -> Provider {
        Provider(id: id, displayName: "Claude", icon: .providerMark("claude"), accountLabel: label)
    }

    private func family(_ accounts: [Provider], lines: [DashboardLine] = []) -> DashboardFamily {
        DashboardFamily(id: "claude", provider: accounts[0], accounts: accounts.map { DashboardAccount(provider: $0, lines: lines) })
    }

    private func header(_ accounts: [Provider], plan: String? = nil) -> some View {
        let family = family(accounts)
        return DashboardProviderHeader(family: family, plan: plan) {
            ProviderIcon(source: family.provider.icon, inset: 0.04)
        }
    }

    private func section(_ family: DashboardFamily, plans: [String: String] = [:]) -> some View {
        DashboardProviderSection(family: family, plans: plans) {
            ProviderIcon(source: family.provider.icon, inset: 0.04)
        } account: { account in
            DashboardAccountRows(
                account: account, plan: plans[account.id], labelWidth: DashboardGrid.minimumLabelWidth,
                showsCaption: family.soleAccount == nil
            )
        }
    }

    private func line(_ data: WidgetData) -> DashboardLine {
        DashboardLine(descriptor: WidgetDescriptor(id: data.title, providerID: "p", metricLabel: data.title, sample: data), data: data)
    }

    private func percent(_ title: String, used: Double) -> WidgetData {
        var data = WidgetData(title: title, icon: .providerMark("claude"), kind: .percent, used: used, limit: 100)
        data.displayMode = .remaining
        return data
    }

    /// Robin: "right align the plan name left-next to the icon". A name that can't fit loses its end
    /// and stops 8 pt before the plan; the plan is whole, ends 8 pt before the logo and is centred on
    /// it; the logo ends 12 pt before the card's edge.
    func testTheHeaderCutsTheNameAndKeepsThePlanBeforeTheLogo() throws {
        let plan = "Pro 200"
        let bitmap = try Bitmap(header([claude("Sunstory Engineering Department of Everything")], plan: plan), width: boxWidth, scale: 2)
        XCTAssertEqual(CGFloat(bitmap.height) / bitmap.scale, DashboardGrid.headerHeight)
        let logoEnd = boxWidth - inset
        let logoStart = logoEnd - DashboardGrid.iconSize
        let planEnd = logoStart - DashboardGrid.columnGap
        let planWidth = try XCTUnwrap(Bitmap(Text(plan).font(.subheadline).fixedSize().padding(20), width: 120, scale: 2).inkSpan())
        let planStart = planEnd - (planWidth.last - planWidth.first)

        let plate = try XCTUnwrap(bitmap.inkSpan(from: planStart - 2, to: logoStart - 2), "no plan drawn")
        XCTAssertEqual(plate.last, planEnd, accuracy: 1.5, "the plan ends 8 pt before the logo")
        XCTAssertEqual(plate.last - plate.first, planWidth.last - planWidth.first, accuracy: 1.5, "the plan is cut")
        XCTAssertNil(bitmap.inkSpan(from: planEnd + 1, to: logoStart - 1), "something sits between the plan and the logo")
        let logo = try XCTUnwrap(bitmap.inkSpan(from: logoStart, to: boxWidth), "no logo drawn")
        XCTAssertEqual(logo.last, logoEnd, accuracy: 1.5, "the logo ends 12 pt before the edge")

        let title = try XCTUnwrap(bitmap.inkSpan(from: 0, to: planStart - 1), "no title drawn")
        XCTAssertEqual(title.first, inset, accuracy: 1.5, "the title starts 12 pt in")
        XCTAssertLessThanOrEqual(title.last, planStart - DashboardGrid.columnGap + 1, "the name runs into the plan")
        XCTAssertGreaterThan(title.last, planStart - 40, "the name is cut far shorter than the room it has")

        let planRows = try XCTUnwrap(bitmap.inkRows(from: planStart, to: planEnd))
        let logoRows = try XCTUnwrap(bitmap.inkRows(from: logoStart, to: logoEnd))
        XCTAssertEqual((planRows.first + planRows.last) / 2, (logoRows.first + logoRows.last) / 2, accuracy: 2, "the plan isn't centred on the logo")
        XCTAssertEqual((planRows.first + planRows.last) / 2, DashboardGrid.headerHeight / 2, accuracy: 2, "the plan isn't centred on the line")
    }

    /// One account's header names it, "Claude — Attention Machine"; several accounts leave the header
    /// to the provider, as does one account named like it. Drawn in the same place and font, an account
    /// named "Claude" spans the provider's header exactly, and a longer name runs further.
    func testAOneAccountHeaderNamesTheAccountAndSeveralShowTheProviderAlone() throws {
        func titleEnd(_ accounts: [Provider]) throws -> CGFloat {
            let bitmap = try Bitmap(header(accounts), width: boxWidth, scale: 2)
            return try XCTUnwrap(bitmap.inkSpan(from: 0, to: boxWidth - inset - DashboardGrid.iconSize - 4)).last
        }
        let providerAlone = try titleEnd([claude("Attention Machine"), claude("Home", "claude@2")])
        XCTAssertEqual(try titleEnd([claude("Claude")]), providerAlone, accuracy: 0.5)
        XCTAssertEqual(try titleEnd([claude(nil)]), providerAlone, accuracy: 0.5)
        XCTAssertGreaterThan(try titleEnd([claude("Attention Machine")]), providerAlone + 40)
        XCTAssertGreaterThan(try titleEnd([claude("sam@hey.com")]), providerAlone + 40, "an account without a name reads its email")
    }

    /// The header's text, each caption and each label start 12 pt in from the card's edge, and the logo
    /// ends 12 pt before it, where the bars end.
    func testTextSharesOneLeadingEdgeAndTheLogoEndsWithTheBars() throws {
        let full = line(percent("Session", used: 0))
        let two = family([claude("Personal"), claude("Work", "claude@2")], lines: [full, line(percent("Weekly", used: 24))])
        let bands = try Bitmap(section(two, plans: ["claude@1": "Max 5x", "claude@2": "Max 5x"]), width: boxWidth, scale: 2).inkBands()
        XCTAssertEqual(bands.count, 7, "the header, then a caption and two rows per account")
        let edges = bands.map(\.first)
        XCTAssertLessThanOrEqual((edges.max() ?? 0) - (edges.min() ?? 0), 1.5, "leading edges \(edges)")
        XCTAssertEqual(edges.min() ?? 0, inset, accuracy: 1.5)
        XCTAssertEqual(bands[0].last, boxWidth - inset, accuracy: 1.5, "the logo ends 12 pt before the edge")
        XCTAssertEqual(bands[2].last, bands[0].last, accuracy: 1, "a full bar ends where the logo does")
    }

    /// Robin: "Everything takes too much space." The steps are pinned in literal points, so changing any
    /// fails here: a 20 pt header, 4 to the card, 8 inside it, 16 per caption, 20 per row, 16 between
    /// accounts, 16 between providers.
    func testSectionsKeepTheirHeights() throws {
        let rows = ["Session", "Weekly", "Fable"].map { line(percent($0, used: 30)) }
        let one = family([claude("Work")], lines: rows)
        XCTAssertEqual(try Bitmap(section(one), width: boxWidth).height, 100, "a header and a card of three rows")
        let two = family([claude("Personal"), claude("Work", "claude@2")], lines: Array(rows.prefix(2)))
        XCTAssertEqual(try Bitmap(section(two), width: boxWidth).height, 168, "two accounts, each a caption and two rows")
        XCTAssertEqual(DashboardGrid.sectionSpacing, 16)
    }

    /// Under the pointer a bar gives way to its text in the same slot: the row stays 20 pt, the text
    /// starts where the bar did and ends inside the row, cut to a shorter candidate when the longest
    /// can't fit. A row without a limit shows its value right-aligned at the bar's end, at its natural
    /// width.
    func testAHoveredRowKeepsItsHeightAndFitsItsText() throws {
        let end = boxWidth - inset
        var red = percent("Weekly", used: 90)
        red.periodDurationMs = 10 * 3600 * 1000
        red.resetsAt = Date().addingTimeInterval(5 * 3600)
        var credits = WidgetData(title: "Credits", icon: .providerMark("codex"), kind: .count, used: 452, limit: nil)
        credits.values = [MetricValue(number: 452, kind: .count, label: "credits")]
        func row(_ data: WidgetData, label: CGFloat, hovered: Bool = false) -> some View {
            DashboardMetricRow(model: data.dashboardRow(), labelWidth: label, hovered: hovered)
                .padding(.horizontal, DashboardGrid.cardPadding)
        }
        for label in [DashboardGrid.minimumLabelWidth, 140] {
            let barStart = inset + label + DashboardGrid.columnGap
            for hovered in [false, true] {
                let bitmap = try Bitmap(row(red, label: label, hovered: hovered), width: boxWidth, scale: 2)
                XCTAssertEqual(CGFloat(bitmap.height) / 2, DashboardGrid.rowHeight, "hovered \(hovered)")
                let slot = try XCTUnwrap(bitmap.inkSpan(from: barStart - 2, to: boxWidth), "an empty slot (label \(label), hovered \(hovered))")
                XCTAssertEqual(slot.first, barStart, accuracy: 1.5, "the slot doesn't start after the label column (label \(label), hovered \(hovered))")
                XCTAssertLessThanOrEqual(slot.last, end + 0.5, "the slot runs past the row (label \(label), hovered \(hovered))")
                if hovered {
                    XCTAssertGreaterThan(slot.last - slot.first, 60, "no text under the pointer (label \(label))")
                }
            }
        }
        let value = try Bitmap(row(credits, label: 96), width: boxWidth, scale: 2)
        let drawn = try XCTUnwrap(value.inkSpan(from: inset + 96 + 2, to: boxWidth))
        let alone = try XCTUnwrap(Bitmap(Text("452 credits").font(.body).monospacedDigit().fixedSize().padding(20), width: 200, scale: 2).inkSpan())
        XCTAssertEqual(drawn.last, end, accuracy: 1.5, "the value isn't right-aligned at the bar's end")
        XCTAssertEqual(drawn.last - drawn.first, alone.last - alone.first, accuracy: 1, "the value shrank")
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

    /// Ink is a pixel that differs clearly from its row's background, sampled 6 pt in from the leading
    /// edge, where only a card's rounded edge can be.
    private func isInk(_ x: Int, _ y: Int) -> Bool {
        let (p, q) = (self[x, y], self[Int(6 * scale), y])
        return max(abs(p.0 - q.0), abs(p.1 - q.1), abs(p.2 - q.2), abs(p.3 - q.3)) > 40
    }

    /// The first and last ink between two x positions in points (the whole width by default), or `nil`
    /// when there is none.
    func inkSpan(from start: CGFloat = 0, to end: CGFloat? = nil) -> Band? {
        let columns = max(0, Int(start * scale))..<min(width, end.map { Int($0 * scale) } ?? width)
        let inked = columns.filter { x in (0..<height).contains { isInk(x, $0) } }
        guard let first = inked.first, let last = inked.last else { return nil }
        return Band(first: CGFloat(first) / scale, last: CGFloat(last + 1) / scale)
    }

    /// The first and last ink row between two x positions, in points from the top.
    func inkRows(from start: CGFloat, to end: CGFloat) -> Band? {
        let columns = max(0, Int(start * scale))..<min(width, Int(end * scale))
        let inked = (0..<height).filter { y in columns.contains { isInk($0, y) } }
        guard let first = inked.first, let last = inked.last else { return nil }
        return Band(first: CGFloat(first) / scale, last: CGFloat(last + 1) / scale)
    }

    /// Each horizontal band of ink, top to bottom: a line of text, or the provider's mark. The 6 pt at
    /// either side hold only a grouped box's rounded edge, and so do bands under 4 pt tall, so neither
    /// counts.
    func inkBands() -> [Band] {
        let background = Int(6 * scale)
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

import SwiftUI
import XCTest
@testable import OpenUsage

/// The provider's header and card, as drawn: the plan sits 8 pt before the logo and nothing on the line
/// is ever cut — a name that doesn't fit moves to the account's caption; the header's text, every
/// caption and every label start 12 pt in, and the logo ends where the reset column does; the heights
/// are literal points; a row's columns sit at their fixed x.
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
        return section(family, plans: Dictionary(uniqueKeysWithValues: accounts.compactMap { account in plan.map { (account.id, $0) } })).header
    }

    private func section(_ family: DashboardFamily, plans: [String: String] = [:]) -> DashboardProviderSection<ProviderIcon, DashboardAccountRows> {
        DashboardProviderSection(family: family, plans: plans) {
            ProviderIcon(source: family.provider.icon, inset: 0.04)
        } account: { account, captioned in
            DashboardAccountRows(account: account, plan: plans[account.id], captioned: captioned)
        }
    }

    private func line(_ data: WidgetData) -> DashboardLine {
        DashboardLine(descriptor: WidgetDescriptor(id: data.title, providerID: "p", metricLabel: data.title, sample: data), data: data)
    }

    private func percent(_ title: String, used: Double, resetsIn: TimeInterval? = nil) -> WidgetData {
        var data = WidgetData(title: title, icon: .providerMark("claude"), kind: .percent, used: used, limit: 100)
        data.displayMode = .remaining
        data.resetsAt = resetsIn.map { Date().addingTimeInterval($0) }
        return data
    }

    /// Robin: "right align the plan name left-next to the icon". The plan is whole, ends 8 pt before the
    /// logo and is centred on it; the logo ends 12 pt before the card's edge; the name stops at least
    /// 8 pt before the plan.
    func testTheHeaderKeepsThePlanBeforeTheLogo() throws {
        let plan = "Pro 200"
        let bitmap = try Bitmap(header([claude("Sunstory")], plan: plan), width: boxWidth, scale: 2)
        XCTAssertEqual(CGFloat(bitmap.height) / bitmap.scale, DashboardGrid.headerHeight)
        let logoEnd = boxWidth - inset
        let logoStart = logoEnd - DashboardGrid.iconSize
        let planEnd = logoStart - DashboardGrid.columnGap
        let planWidth = try XCTUnwrap(Bitmap(Text(plan).font(DashboardGrid.planFont).fixedSize().padding(20), width: 120, scale: 2).inkSpan())
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
        XCTAssertGreaterThan(title.last, inset + 100, "the name is missing")

        let planRows = try XCTUnwrap(bitmap.inkRows(from: planStart, to: planEnd))
        let logoRows = try XCTUnwrap(bitmap.inkRows(from: logoStart, to: logoEnd))
        XCTAssertEqual((planRows.first + planRows.last) / 2, (logoRows.first + logoRows.last) / 2, accuracy: 2, "the plan isn't centred on the logo")
        XCTAssertEqual((planRows.first + planRows.last) / 2, DashboardGrid.headerHeight / 2, accuracy: 2, "the plan isn't centred on the line")
    }

    /// Robin's panel read "Grok — rob@s…ry.com  SuperGrok Heavy": nothing is ever truncated or shrunk
    /// at the 340 pt panel. When "Provider — account", the plan and the logo don't fit the line, the
    /// card takes the several-accounts form: the header reads the provider alone with the logo, and the
    /// caption inside the card carries the name and the plan, as it does in a card of several accounts.
    /// Decided by measuring, not by counting characters: "Codex — sam@hey.com  Plus" fits and keeps the
    /// one-account form.
    func testANameThatDoesNotFitTheHeaderMovesToTheCaptionWithItsPlan() throws {
        let grok = Provider(id: "grok@1", displayName: "Grok", icon: .providerMark("grok"), accountLabel: "rob@sunstory.com")
        let codex = Provider(id: "codex@1", displayName: "Codex", icon: .providerMark("codex"), accountLabel: "sam@hey.com")
        let weekly = line(percent("Weekly", used: 10, resetsIn: 3 * 86_400))
        func family(_ provider: Provider) -> DashboardFamily {
            DashboardFamily(id: provider.id, provider: provider, accounts: [DashboardAccount(provider: provider, lines: [weekly])])
        }
        XCTAssertFalse(DashboardHeaderLine.fits(provider: grok, name: "rob@sunstory.com", plan: "SuperGrok Heavy", width: DashboardGrid.cardWidth))
        XCTAssertTrue(DashboardHeaderLine.fits(provider: codex, name: "sam@hey.com", plan: "Plus", width: DashboardGrid.cardWidth))

        let fallback = try Bitmap(section(family(grok), plans: ["grok@1": "SuperGrok Heavy"]), width: boxWidth, scale: 2)
        let fallbackBands = fallback.inkBands()
        XCTAssertEqual(fallbackBands.count, 3, "the header, the caption, the row")
        XCTAssertEqual(CGFloat(fallback.height) / 2, DashboardGrid.headerHeight + DashboardGrid.headerGap + 2 * DashboardGrid.cardPadding + DashboardGrid.captionHeight + DashboardGrid.rowHeight)
        let titleEnd = boxWidth - inset - DashboardGrid.iconSize - 4
        let grokAlone = try XCTUnwrap(Bitmap(header([Provider(id: "grok@1", displayName: "Grok", icon: .providerMark("grok"))]), width: boxWidth, scale: 2).inkSpan(from: 0, to: titleEnd))
        let fallbackHeader = try XCTUnwrap(Bitmap(header([grok], plan: "SuperGrok Heavy"), width: boxWidth, scale: 2).inkSpan(from: 0, to: titleEnd))
        XCTAssertEqual(fallbackHeader.last, grokAlone.last, accuracy: 0.5, "the header reads more than the provider, or carries the plan")
        XCTAssertEqual(fallbackBands[0].last, boxWidth - inset, accuracy: 1.5, "the logo ends 12 pt before the edge")
        let caption = try Bitmap(DashboardAccountCaption(account: family(grok).accounts[0], plan: "SuperGrok Heavy").padding(.horizontal, DashboardGrid.cardPadding), width: boxWidth, scale: 2).inkBands()
        XCTAssertEqual(fallbackBands[1].first, caption[0].first, accuracy: 0.5, "the caption isn't the several-accounts caption")
        XCTAssertEqual(fallbackBands[1].last, caption[0].last, accuracy: 0.5, "the caption's plan doesn't end where a several-accounts caption's does")

        let fits = try Bitmap(section(family(codex), plans: ["codex@1": "Plus"]), width: boxWidth, scale: 2)
        XCTAssertEqual(fits.inkBands().count, 2, "the header and the row, no caption")
        XCTAssertEqual(CGFloat(fits.height) / 2, DashboardGrid.headerHeight + DashboardGrid.headerGap + 2 * DashboardGrid.cardPadding + DashboardGrid.rowHeight)
        let fitsHeader = try XCTUnwrap(Bitmap(header([codex], plan: "Plus"), width: boxWidth, scale: 2).inkSpan(from: 0, to: titleEnd))
        XCTAssertGreaterThan(fitsHeader.last, grokAlone.last + 100, "the header doesn't name the account")
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

    /// A sole account named like its provider reads as the provider alone, its plan and status on the
    /// header and no caption repeating the name below it (Robin's OpenCode card); one whose own name
    /// doesn't fit the line moves its name and plan to the caption, leaving the header the provider.
    func testAnAccountNamedLikeItsProviderKeepsThePlanOnTheHeaderWithoutACaption() throws {
        let rows = [line(percent("Session", used: 8)), line(percent("Weekly", used: 81))]
        let unnamed = section(family([claude("Claude")], lines: rows), plans: ["claude@1": "Max 20x"])
        XCTAssertEqual(try Bitmap(unnamed, width: boxWidth).inkBands().count, 3, "a header and two rows, no caption")
        XCTAssertEqual(try Bitmap(unnamed, width: boxWidth).height, 76, "a header and a card of two rows")
        let unnamedHeader = try Bitmap(unnamed.header, width: boxWidth, scale: 2)
        XCTAssertNotNil(unnamedHeader.inkSpan(from: boxWidth / 2, to: boxWidth - inset - DashboardGrid.iconSize - 4), "the plan is on the header")

        let overflowing = section(family([claude("rob@sunstory.com")], lines: rows), plans: ["claude@1": "An Especially Wide Plan Name"])
        XCTAssertEqual(try Bitmap(overflowing, width: boxWidth).inkBands().count, 4, "a header, a caption and two rows")
        let overflowingHeader = try Bitmap(overflowing.header, width: boxWidth, scale: 2)
        XCTAssertNil(overflowingHeader.inkSpan(from: boxWidth / 2, to: boxWidth - inset - DashboardGrid.iconSize - 4), "the plan left the header")
    }

    /// The header's text, each caption and each label start 12 pt in from the card's edge; the logo, the
    /// plan on a caption and the reset column all end 12 pt before it.
    func testTextSharesOneLeadingEdgeAndTheLogoEndsWithTheResets() throws {
        let session = line(percent("Session", used: 0, resetsIn: 3 * 3600))
        let two = family([claude("Personal"), claude("Work", "claude@2")], lines: [session, line(percent("Weekly", used: 24, resetsIn: 86_400))])
        let bands = try Bitmap(section(two, plans: ["claude@1": "Max 5x", "claude@2": "Max 5x"]), width: boxWidth, scale: 2).inkBands()
        XCTAssertEqual(bands.count, 7, "the header, then a caption and two rows per account")
        let edges = bands.map(\.first)
        XCTAssertLessThanOrEqual((edges.max() ?? 0) - (edges.min() ?? 0), 1.5, "leading edges \(edges)")
        XCTAssertEqual(edges.min() ?? 0, inset, accuracy: 1.5)
        XCTAssertEqual(bands[0].last, boxWidth - inset, accuracy: 1.5, "the logo ends 12 pt before the edge")
        XCTAssertEqual(bands[1].last, bands[0].last, accuracy: 1.5, "the caption's plan ends where the logo does")
        XCTAssertEqual(bands[2].last, bands[0].last, accuracy: 1.5, "the reset ends where the logo does")
    }

    /// Robin: "Everything takes too much space." The steps are pinned in literal points, so changing any
    /// fails here: a 16 pt header (one Headline line), 4 to the card, 8 inside it, 14 per caption (one
    /// Subheadline line), 20 per row, 16 between accounts, 16 between providers.
    func testSectionsKeepTheirHeights() throws {
        let rows = ["Session", "Weekly", "Fable"].map { line(percent($0, used: 30)) }
        let one = family([claude("Work")], lines: rows)
        XCTAssertEqual(try Bitmap(section(one), width: boxWidth).height, 96, "a header and a card of three rows")
        let two = family([claude("Personal"), claude("Work", "claude@2")], lines: Array(rows.prefix(2)))
        XCTAssertEqual(try Bitmap(section(two), width: boxWidth).height, 160, "two accounts, each a caption and two rows")
        XCTAssertEqual(DashboardGrid.sectionSpacing, 16)
        XCTAssertEqual(DashboardGrid.headerHeight, DashboardGrid.lineHeight(.preferredFont(forTextStyle: .headline)))
        XCTAssertEqual(DashboardGrid.captionHeight, DashboardGrid.lineHeight(.preferredFont(forTextStyle: .subheadline)))
        XCTAssertEqual(DashboardGrid.iconSize, DashboardGrid.headerHeight, "the logo isn't as tall as the header's line")
    }

    /// A row at rest shows every column in its fixed place: the bar starts 8 pt after the 86 pt label
    /// column and fills its slot, the value is right-aligned in its 52 pt column, the reset in its 56 pt
    /// column ending 12 pt before the card's edge. A row without a limit shows its value where the bar
    /// would start, at its natural width.
    func testARowShowsItsBarValueAndResetInTheirColumns() throws {
        let end = boxWidth - inset
        let barStart = inset + DashboardGrid.labelWidth + DashboardGrid.columnGap
        let resetStart = end - DashboardGrid.resetWidth
        let valueStart = resetStart - DashboardGrid.columnGap - DashboardGrid.valueWidth
        let barEnd = valueStart - DashboardGrid.columnGap
        let full = percent("Weekly", used: 0, resetsIn: 5 * 3600)
        var credits = WidgetData(title: "Credits", icon: .providerMark("codex"), kind: .count, used: 452, limit: nil)
        credits.values = [MetricValue(number: 452, kind: .count, label: "credits")]
        func row(_ data: WidgetData) -> some View {
            DashboardMetricRow(model: data.dashboardRow()).padding(.horizontal, DashboardGrid.cardPadding)
        }

        let bitmap = try Bitmap(row(full), width: boxWidth, scale: 2)
        XCTAssertEqual(CGFloat(bitmap.height) / 2, DashboardGrid.rowHeight)
        let label = try XCTUnwrap(bitmap.inkSpan(from: 0, to: barStart - 2), "no label")
        XCTAssertEqual(label.first, inset, accuracy: 1.5)
        let bar = try XCTUnwrap(bitmap.inkSpan(from: barStart - 2, to: barEnd + 2), "no bar")
        XCTAssertEqual(bar.first, barStart, accuracy: 1.5, "the bar doesn't start after the label column")
        XCTAssertEqual(bar.last, barEnd, accuracy: 1.5, "the bar doesn't fill its slot")
        let value = try XCTUnwrap(bitmap.inkSpan(from: valueStart - 2, to: resetStart - 4), "no value at rest")
        XCTAssertEqual(value.last, valueStart + DashboardGrid.valueWidth, accuracy: 1.5, "the value isn't right-aligned in its column")
        let reset = try XCTUnwrap(bitmap.inkSpan(from: resetStart - 2, to: boxWidth), "no reset at rest")
        XCTAssertEqual(reset.last, end, accuracy: 1.5, "the reset isn't right-aligned at the card's inset")
        XCTAssertGreaterThan(reset.last - reset.first, 8, "the reset is empty")

        let plain = try Bitmap(row(credits), width: boxWidth, scale: 2)
        let drawn = try XCTUnwrap(plain.inkSpan(from: barStart - 2, to: boxWidth))
        let alone = try XCTUnwrap(Bitmap(Text("452 credits").font(DashboardMetricRow.font).monospacedDigit().fixedSize().padding(20), width: 200, scale: 2).inkSpan())
        XCTAssertEqual(drawn.first, barStart, accuracy: 1.5, "the value doesn't start where the bar would")
        XCTAssertEqual(drawn.last - drawn.first, alone.last - alone.first, accuracy: 1, "the value shrank")
    }

    /// A row running out shows the flame before its value, inside the value column, and nothing else
    /// moves: the label, the bar, the value's right edge and the reset sit where they do on a row at
    /// rest, and even the widest value, "100%", keeps the flame inside the column.
    func testTheFlameSitsInTheValueColumnAndMovesNothing() throws {
        let end = boxWidth - inset
        let resetStart = end - DashboardGrid.resetWidth
        let valueStart = resetStart - DashboardGrid.columnGap - DashboardGrid.valueWidth
        let barEnd = valueStart - DashboardGrid.columnGap
        func row(flame: Bool, value: String = "100%") -> some View {
            DashboardMetricRow(model: DashboardRowModel(label: "Weekly", mark: .bar(fill: 0.6, severity: flame ? .critical : .normal, value: value, reset: "3d 12h", flame: flame)))
                .padding(.horizontal, DashboardGrid.cardPadding)
        }
        let rest = try Bitmap(row(flame: false), width: boxWidth, scale: 2)
        let hot = try Bitmap(row(flame: true), width: boxWidth, scale: 2)
        for (name, from, to) in [("label", 0, valueStart - DashboardGrid.columnGap - 60), ("bar", valueStart - DashboardGrid.columnGap - 60, barEnd + 2), ("reset", resetStart - 2, boxWidth)] {
            let atRest = try XCTUnwrap(rest.inkSpan(from: from, to: to), "no \(name) at rest")
            let withFlame = try XCTUnwrap(hot.inkSpan(from: from, to: to), "no \(name) with the flame")
            XCTAssertEqual(withFlame.first, atRest.first, accuracy: 0.5, "the flame moved the \(name)")
            XCTAssertEqual(withFlame.last, atRest.last, accuracy: 0.5, "the flame moved the \(name)")
        }
        let restValue = try XCTUnwrap(rest.inkSpan(from: barEnd + 2, to: resetStart - 4))
        let hotValue = try XCTUnwrap(hot.inkSpan(from: barEnd + 2, to: resetStart - 4))
        XCTAssertEqual(hotValue.last, restValue.last, accuracy: 0.5, "the flame moved the value")
        XCTAssertLessThan(hotValue.first, restValue.first - 6, "no flame before the value")
        XCTAssertGreaterThanOrEqual(hotValue.first, valueStart - 0.5, "the flame runs out of the value column")
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

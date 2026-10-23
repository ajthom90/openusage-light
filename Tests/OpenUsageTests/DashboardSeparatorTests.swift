import AppKit
import SwiftUI
import XCTest
@testable import OpenUsage

/// The dashboard has no cards: provider sections sit straight on the panel, and one hairline in the
/// system separator colour runs edge to edge between two of them, with none above the first section or
/// below the last.
@MainActor
final class DashboardSeparatorTests: XCTestCase {
    func testOneFullWidthHairlineSitsBetweenEachTwoSections() async throws {
        let suite = "OpenUsageTests.DashboardSeparator.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let store = AccountStore(defaults: defaults, vault: InMemoryCredentialVault())
        let container = await AppContainer(accounts: store, defaults: defaults)
        let accounts: [(ProviderKind, String)] = [(.claude, "Personal"), (.claude, "Work"), (.codex, "Sunstory"), (.openrouter, "OpenRouter")]
        for (kind, label) in accounts {
            store.add(kind: kind, label: label, credential: .apiKey("key"))
        }
        for _ in 0..<200 where container.layout.displayGroups.count < accounts.count {
            try await Task.sleep(for: .milliseconds(5))
        }

        // The dashboard's own list, as `DashboardContentView` hosts it on the tray. The scroll view around it
        // doesn't draw into `cacheDisplay`.
        let view = NSHostingView(rootView: WidgetGroupedListView(reorderSpaceName: "list", reorderLift: .constant(nil))
            .environment(container)
            .environment(container.layout)
            .environment(container.dataStore)
            .environment(container.renaming)
            .environment(\.colorScheme, .light)
            .frame(width: PanelMetrics.width)
            .background(Theme.traySurface))
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        let panel = MenuBarPanel(contentRect: view.frame)
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .aqua)
        panel.contentView = view
        panel.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        panel.orderFrontRegardless()
        addTeardownBlock { panel.close() }
        try await Task.sleep(for: .milliseconds(300))
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        func light(_ color: NSColor) -> NSColor {
            var resolved = color
            NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance { resolved = color.usingColorSpace(.sRGB) ?? color }
            return resolved
        }
        let tray = light(Theme.trayNSColor)
        func pixel(_ x: Int, _ y: Int) -> NSColor { rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0) }
        func differs(_ a: NSColor, _ b: NSColor, by limit: CGFloat) -> Bool {
            max(abs(a.redComponent - b.redComponent), abs(a.greenComponent - b.greenComponent), abs(a.blueComponent - b.blueComponent)) > limit
        }
        func isTrayRow(_ y: Int) -> Bool {
            stride(from: 0, to: rep.pixelsWide, by: 4).allSatisfy { !differs(pixel($0, y), tray, by: 0.01) }
        }
        /// A row that is one colour, darker than the tray, from the panel's first pixel to its last.
        func isLineRow(_ y: Int) -> Bool {
            let first = pixel(0, y)
            guard differs(first, tray, by: 0.03) else { return false }
            return (0..<rep.pixelsWide).allSatisfy { !differs(pixel($0, y), first, by: 0.01) }
        }

        let lines = (0..<rep.pixelsHigh).filter(isLineRow)
        XCTAssertEqual(lines.count, 2, "three sections, so two separators, each one pixel thick; rows \(lines)")
        let separator = light(.separatorColor)
        let expected = tray.redComponent * (1 - separator.alphaComponent) + separator.redComponent * separator.alphaComponent
        let gap = Int(DashboardSpacing.sectionPadding * scale)
        for y in lines {
            XCTAssertEqual(pixel(rep.pixelsWide / 2, y).redComponent, expected, accuracy: 0.03, "the separator colour at row \(y)")
            let padding = (Array(y - gap..<y) + Array(y + 1...y + gap)).filter { (0..<rep.pixelsHigh).contains($0) }
            XCTAssertEqual(padding.count, 2 * gap, "row \(y) is at the list's end")
            XCTAssertTrue(padding.allSatisfy(isTrayRow), "the separator sits in \(DashboardSpacing.sectionPadding) pt of empty padding on each side, row \(y)")
        }
    }
}

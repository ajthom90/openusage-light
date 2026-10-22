import SwiftUI
import XCTest
@testable import OpenUsage

@MainActor
final class ProviderHeaderLayoutTests: XCTestCase {
    private let longPlan = String(repeating: "Future Enterprise Entitlement ", count: 12)
    private let codexProvider = Provider(id: "codex", displayName: "Codex", icon: .providerMark("codex"))

    func testDashboardAccountLineFitsOversizedPlanInBothDensities() throws {
        for density in DensitySetting.allCases {
            let suite = "ProviderHeaderLayoutTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defaults.set(density.rawValue, forKey: DensitySetting.key)
            defer { defaults.removePersistentDomain(forName: suite) }

            let account = DashboardAccount(provider: codexProvider, lines: [], extraLines: [], resets: nil)
            let section = DashboardAccountSection(
                account: account,
                plan: longPlan,
                notice: "Refresh failed"
            ) { _ in EmptyView() }
            .defaultAppStorage(defaults)
            .environment(\.hoverTooltipsDisabled, true)

            // 320pt popover minus the 14pt outer padding and the 14pt card padding on each side.
            try assertFits(section, width: 264)
        }
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

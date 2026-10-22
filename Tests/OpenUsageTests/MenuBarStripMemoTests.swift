import XCTest
@testable import OpenUsage

/// Covers the strip renderer's single-entry memo (#18): equal content return the
/// previously rendered `NSImage` instance — so the hundreds of observation-loop re-renders between
/// real data changes never re-run `ImageRenderer`, and `StatusItemImageUpdater` can skip `apply`
/// on that same instance — while a changed value renders fresh.
@MainActor
final class MenuBarStripMemoTests: XCTestCase {
    func testEqualContentReturnsSameImageInstance() throws {
        let first = try XCTUnwrap(MenuBarStripRenderer.image(for: makeContent(value: "42%")))
        let second = try XCTUnwrap(MenuBarStripRenderer.image(for: makeContent(value: "42%")))
        XCTAssertIdentical(first, second)
    }

    func testChangedValueRendersFreshImage() throws {
        let first = try XCTUnwrap(MenuBarStripRenderer.image(for: makeContent(value: "42%")))
        let changed = try XCTUnwrap(MenuBarStripRenderer.image(for: makeContent(value: "43%")))
        XCTAssertNotIdentical(first, changed)
    }

    func testUnchangedMemoizedImageIsNotApplied() throws {
        var applied: [NSImage] = []
        var gate = StatusItemImageUpdater.ApplyGate()
        let first = try XCTUnwrap(MenuBarStripRenderer.image(for: makeContent(value: "42%")))
        let second = try XCTUnwrap(MenuBarStripRenderer.image(for: makeContent(value: "42%")))
        gate.apply(first, using: { applied.append($0) })
        gate.apply(second, using: { applied.append($0) })
        XCTAssertIdentical(first, second)
        XCTAssertEqual(applied.count, 1)
        XCTAssertIdentical(applied[0], first)
    }

    func testChangedImageIsApplied() throws {
        var applied: [NSImage] = []
        var gate = StatusItemImageUpdater.ApplyGate()
        let first = try XCTUnwrap(MenuBarStripRenderer.image(for: makeContent(value: "42%")))
        let changed = try XCTUnwrap(MenuBarStripRenderer.image(for: makeContent(value: "43%")))
        gate.apply(first, using: { applied.append($0) })
        gate.apply(changed, using: { applied.append($0) })
        gate.apply(changed, using: { applied.append($0) })
        XCTAssertNotIdentical(first, changed)
        XCTAssertEqual(applied.count, 2)
        XCTAssertIdentical(applied[0], first)
        XCTAssertIdentical(applied[1], changed)
    }

    private func makeContent(value: String) -> MenuBarContent {
        let metric = MenuBarContent.Metric(
            id: "claude.session", label: "Session", value: value,
            hasData: true
        )
        return MenuBarContent(
            groups: [MenuBarContent.Group(
                providerID: "claude",
                displayName: "Claude",
                icon: .providerMark("claude"),
                metrics: [metric]
            )]
        )
    }
}

import AppKit
import XCTest
@testable import OpenUsage
@testable import OpenUsageCore

@MainActor
final class ProviderMarksTests: XCTestCase {
    func testProviderVectorMarksLoadWithoutFallbacks() throws {
        for id in ["claude", "codex", "cursor", "antigravity", "copilot", "grok", "ollama", "opencode", "openrouter", "zai"] {
            let mark = try XCTUnwrap(ProviderMarks.mark(for: id), "\(id) should load a vector mark")
            XCTAssertFalse(mark.path.isEmpty, "\(id) mark must carry SVG path data")
        }
    }

    /// Muse Code's official mark comes as a bitmap: it has no vector mark, and its PNG loads with an alpha
    /// channel so it can be tinted like the others.
    func testMuseCodeUsesItsBundledBitmap() throws {
        XCTAssertNil(ProviderMarks.mark(for: "musecode"))
        let image = try XCTUnwrap(ProviderMarks.raster(for: "musecode"))
        let bitmap = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
        XCTAssertTrue(bitmap.hasAlpha, "a silhouette needs transparency")
        XCTAssertGreaterThan(bitmap.pixelsWide, bitmap.pixelsHigh, "the mark is wider than tall")
        XCTAssertNil(ProviderMarks.raster(for: "claude"), "providers with vector marks have no bitmap")
    }
}

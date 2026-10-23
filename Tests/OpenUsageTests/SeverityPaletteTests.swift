import AppKit
import SwiftUI
import XCTest
@testable import OpenUsage

/// One severity palette: blue, orange, red. Each severity maps to its system colour, and the meter
/// bar, the ↺ tag, the resets timeline dot and the claim banner all paint that same colour. The views
/// are rasterized and their dominant opaque colour is matched to the nearest candidate colour, so a
/// surface that drifts to yellow, the accent colour, or SwiftUI's own orange/red fails here.
@MainActor
final class SeverityPaletteTests: XCTestCase {
    private let d: TimeInterval = 86400

    private static let palette: [(WidgetData.MeterSeverity, String)] = [
        (.normal, "systemBlue"), (.warning, "systemOrange"), (.critical, "systemRed"),
    ]

    private static let candidates: [(String, NSColor)] = [
        ("systemBlue", .systemBlue), ("systemOrange", .systemOrange), ("systemRed", .systemRed),
        ("systemYellow", .systemYellow), ("controlAccent", .controlAccentColor),
        ("swiftUIOrange", NSColor(Color.orange)), ("swiftUIRed", NSColor(Color.red)),
    ]

    func testEachSeverityMapsToItsSystemColour() {
        for (severity, name) in Self.palette {
            XCTAssertEqual(Self.nearest(NSColor(Theme.severityColor(severity))), name, "\(severity)")
        }
        XCTAssertEqual(Self.nearest(NSColor(Theme.severityColor(nil))), "systemBlue")
    }

    func testMeterChipTimelineDotAndBannerAgree() throws {
        for (severity, name) in Self.palette {
            let meter = UsageMeterBar(data: percent(), state: .level(severity)).frame(width: 60)
            XCTAssertEqual(try dominant(meter), name, "meter \(severity)")

            let expiry = Date().addingTimeInterval(expiryOffset(severity))
            XCTAssertEqual(try dominant(ResetCountChip(data: resets([expiry]))), name, "↺ tag \(severity)")

            let timeline = RateLimitResetsDetail(count: 1, expiries: [expiry], onHoverChange: { _ in })
            XCTAssertEqual(try dominant(timeline), name, "timeline dot \(severity)")
        }

        let banners: [(ResetClaimOutcome, String)] = [
            (.nothingToReset, "systemBlue"), (.unavailableNow(until: nil), "systemOrange"), (.failed(.refused), "systemRed"),
        ]
        for (outcome, name) in banners {
            XCTAssertEqual(Self.nearest(NSColor(RateLimitResetsDetail.banner(for: outcome).tint)), name, "banner \(outcome)")
        }
    }

    func testSourcesNeverUseYellow() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        let banned = try NSRegularExpression(pattern: #"systemYellow|\.yellow\b"#)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let hit = banned.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
            XCTAssertNil(hit, "\(file.lastPathComponent) uses yellow; take the warning colour from Theme.severityColor")
        }
    }

    // MARK: - Fixtures

    private func expiryOffset(_ severity: WidgetData.MeterSeverity) -> TimeInterval {
        switch severity {
        case .critical: return 1 * d
        case .warning: return 5 * d
        case .normal: return 20 * d
        }
    }

    private func percent() -> WidgetData {
        WidgetData(title: "Session", icon: .providerMark("claude"), kind: .percent, used: 100, limit: 100)
    }

    private func resets(_ expiries: [Date]) -> WidgetData {
        var data = WidgetData(title: "Rate Limit Resets", icon: .providerMark("codex"), kind: .count, used: Double(expiries.count), limit: nil)
        data.values = [MetricValue(number: Double(expiries.count), kind: .count, label: "available")]
        data.showsResetExpiries = true
        data.expiriesAt = expiries
        return data
    }

    // MARK: - Colour sampling

    /// The most common fully opaque, saturated pixel of the rendered view (fills and glyphs, never the
    /// gray text or the translucent capsule behind the ↺ tag), named by its nearest candidate colour.
    private func dominant(_ view: some View) throws -> String {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage, "render failed")
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var counts: [UInt32: Int] = [:]
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] == 255 {
            let r = pixels[i], g = pixels[i + 1], b = pixels[i + 2]
            guard Int(max(r, g, b)) - Int(min(r, g, b)) > 64 else { continue }
            counts[UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b), default: 0] += 1
        }
        let key = try XCTUnwrap(counts.max { $0.value < $1.value }?.key, "no saturated pixels")
        let rgb = SIMD3(Double(key >> 16 & 0xFF), Double(key >> 8 & 0xFF), Double(key & 0xFF)) / 255
        return Self.nearest(rgb)
    }

    private static func nearest(_ color: NSColor) -> String {
        nearest(resolve(color, .aqua))
    }

    /// The candidate closest to `rgb`, each compared in both its light and dark appearance.
    private static func nearest(_ rgb: SIMD3<Double>) -> String {
        candidates.min { distance(rgb, $0.1) < distance(rgb, $1.1) }!.0
    }

    private static func distance(_ rgb: SIMD3<Double>, _ color: NSColor) -> Double {
        [NSAppearance.Name.aqua, .darkAqua].map { name in
            let delta = resolve(color, name) - rgb
            return (delta * delta).sum()
        }.min()!
    }

    private static func resolve(_ color: NSColor, _ appearance: NSAppearance.Name) -> SIMD3<Double> {
        var rgb = SIMD3<Double>(repeating: -1)
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            let c = color.usingColorSpace(.sRGB)!
            rgb = SIMD3(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
        }
        return rgb
    }
}

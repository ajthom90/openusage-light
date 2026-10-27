import XCTest

/// `OpenUsageCore` is what a Windows or Linux app would build on, so it may import only what exists
/// on every platform Swift runs on. An `import AppKit` or `import os` slipping in would compile on a
/// Mac and break the other ports without a failing test; this makes it fail here.
final class CoreImportsTests: XCTestCase {
    private static let portableModules: Set<String> = ["Foundation"]

    private var coreDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/OpenUsageCore")
    }

    private func coreSources() throws -> [URL] {
        let files = FileManager.default.enumerator(at: coreDirectory, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        XCTAssertFalse(files.isEmpty, "found no sources under \(coreDirectory.path)")
        return files
    }

    func testCoreImportsOnlyPortableModules() throws {
        for file in try coreSources() {
            let source = try String(contentsOf: file, encoding: .utf8)
            for line in source.split(separator: "\n") where line.hasPrefix("import ") || line.hasPrefix("@testable import ") {
                let module = line.split(separator: " ").last.map(String.init) ?? ""
                XCTAssertTrue(
                    Self.portableModules.contains(module),
                    "\(file.lastPathComponent) imports \(module); OpenUsageCore may import only \(Self.portableModules.sorted())"
                )
            }
        }
    }

    func testCoreDoesNotNameApplePlatformTypes() throws {
        let apple = try NSRegularExpression(pattern: #"\b(NSColor|NSImage|NSApplication|UserDefaults\.standard|SecItem|OSAllocatedUnfairLock|Logger\()"#)
        for file in try coreSources() {
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            XCTAssertNil(apple.firstMatch(in: source, range: range), "\(file.lastPathComponent) names an Apple-only API")
        }
    }
}

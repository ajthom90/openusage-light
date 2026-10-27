import XCTest

/// `OpenUsageCore` is what a Windows or Linux app would build on, so it may import only what exists
/// on every platform Swift runs on. An `import AppKit` or `import os` slipping in would compile on a
/// Mac and break the other ports without a failing test; this makes it fail here.
final class CoreImportsTests: XCTestCase {
    private static let portableModules: Set<String> = ["Foundation", "FoundationNetworking", "Observation"]

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
            // A Windows checkout may use CRLF line endings, which Swift reads as one character, not a newline.
            let source = try String(contentsOf: file, encoding: .utf8).replacingOccurrences(of: "\r\n", with: "\n")
            let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (index, line) in lines.enumerated() where line.hasPrefix("import ") || line.hasPrefix("@testable import ") {
                let module = line.split(separator: " ").last.map(String.init) ?? ""
                // A module that exists only on some platforms is fine behind `#if canImport(<module>)`.
                let guarded = index > 0 && lines[index - 1].trimmingCharacters(in: .whitespaces) == "#if canImport(\(module))"
                XCTAssertTrue(
                    Self.portableModules.contains(module) || guarded,
                    "\(file.lastPathComponent) imports \(module); OpenUsageCore may import only \(Self.portableModules.sorted()) unguarded"
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

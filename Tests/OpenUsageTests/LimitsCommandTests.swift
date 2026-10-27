import XCTest
@testable import OpenUsage
@testable import OpenUsageCore

/// Every public resource key is read from a dashboard row, so a row renamed in a runtime would
/// silently drop its field from the document. This fails first.
@MainActor
final class LimitsRowsTests: XCTestCase {
    func testEveryResourceKeyNamesARealDashboardRow() {
        for kind in ProviderKind.allCases {
            let runtime = AccountProviderRuntime(account: Account(kind: kind, label: "Work"), vault: InMemoryCredentialVault())
            let prefix = runtime.provider.id.count + 1
            let rows = Set(runtime.widgetDescriptors.map { String($0.id.dropFirst(prefix)) })
            for suffix in LimitsProjection.rowSuffixes(for: kind) {
                XCTAssertTrue(rows.contains(suffix), "\(kind.rawValue) has no dashboard row \"\(suffix)\"")
            }
        }
    }
}

@MainActor
final class SavedDashboardOrderTests: XCTestCase {
    /// The command reads the dashboard order straight from settings, so it must read what `LayoutPersistence`
    /// writes.
    func testReadsWhatTheDashboardSaves() {
        let suite = "OpenUsageTests.SavedOrder.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        LayoutPersistence(defaults: defaults, storageKey: LayoutStore.defaultStorageKey).saveProviderOrder(["b@2", "a@1"])
        XCTAssertEqual(SavedDashboardOrder.providerOrder(in: defaults), ["b@2", "a@1"])
    }
}

final class AppPreferencesTests: XCTestCase {
    func testFindsTheEnclosingAppsBundleIdentifierThroughASymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AppPreferencesTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("Fake.app/Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.example.fake", "CFBundleExecutable": "tool", "CFBundlePackageType": "APPL"]
        try (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))
        let tool = contents.appendingPathComponent("MacOS/openusage-cli")
        try Data().write(to: tool)
        let link = root.appendingPathComponent("openusage")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: tool)

        XCTAssertEqual(AppPreferences.bundleIdentifier(containing: tool), "com.example.fake")
        XCTAssertEqual(AppPreferences.bundleIdentifier(containing: link), "com.example.fake")
        XCTAssertNil(AppPreferences.bundleIdentifier(containing: FileManager.default.temporaryDirectory.appendingPathComponent("tool")))
    }
}

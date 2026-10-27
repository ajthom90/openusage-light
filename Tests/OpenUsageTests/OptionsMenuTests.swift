import SwiftUI
import XCTest
@testable import OpenUsage

/// The footer's Options menu: Share Screenshot lives on the dashboard's right-click alone.
@MainActor
final class OptionsMenuTests: XCTestCase {
    func testTheOptionsMenuHasNoShareItem() {
        var contents = ""
        dump(HeaderView(screen: .dashboard).menuItems, to: &contents)

        for title in ["Accounts", "Settings", "Report an Issue…", "About OpenUsage", "Quit OpenUsage"] {
            XCTAssertTrue(contents.contains(title), "the Options menu lost \(title)")
        }
        XCTAssertFalse(contents.localizedCaseInsensitiveContains("Share"), "the Options menu offers a share item")
    }
}

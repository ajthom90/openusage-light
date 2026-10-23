import AppKit
import SwiftUI
import XCTest
@testable import OpenUsage

/// The Accounts list's top bar: its trailing + opens the Add Account sheet, the screen's only way in.
@MainActor
final class PopoverTopBarTests: XCTestCase {
    func testTheAccountsBarsTrailingButtonOpensAddAccount() async throws {
        let suite = "OpenUsageTests.PopoverTopBar.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let container = await AppContainer(
            accounts: AccountStore(defaults: defaults, vault: InMemoryCredentialVault()),
            defaults: defaults
        )
        let layout = container.layout
        layout.screen = .accounts

        let view = VStack(spacing: 0) {
            PopoverTopBar(layout: layout, screen: .accounts, height: 44, horizontalPadding: PanelMetrics.margin)
            AccountListView(reorderSpaceName: "reorder", reorderLift: .constant(nil), frameStore: ReorderFrameStore())
        }
        .frame(width: PanelMetrics.width)
        .environment(container)
        .environment(layout)
        .environment(container.renaming)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        addTeardownBlock {
            window.attachedSheet.map { window.endSheet($0) }
            window.close()
        }
        XCTAssertNil(window.attachedSheet)

        // The trailing button's center: a large circular glass button inset by the bar's padding.
        let point = NSPoint(x: host.bounds.width - PanelMetrics.margin - 14, y: host.bounds.height - 22)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0
            )!)
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(800))

        XCTAssertTrue(layout.isAddingAccount)
        XCTAssertNotNil(window.attachedSheet, "the + didn't present the Add Account sheet")
    }

    func testLeavingAccountsDropsAnOpenAddAccountSheet() {
        let suite = "OpenUsageTests.PopoverTopBar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let layout = LayoutStore(registry: .mock, defaults: defaults, storageKey: "layout")
        layout.screen = .accounts
        layout.isAddingAccount = true

        layout.screen = .dashboard

        XCTAssertFalse(layout.isAddingAccount)
    }
}

import AppKit
import Observation
import SwiftUI
import XCTest
@testable import OpenUsage

/// Cancel, and Escape with it, steps back from a provider's sign-in to the provider list; only on
/// the list does it close the sheet.
@MainActor
final class AddAccountSheetTests: XCTestCase {
    func testCancelOnAProviderStepReturnsToTheListAndCancelOnTheListCloses() async throws {
        let suite = "OpenUsageTests.AddAccountSheet.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let url = try XCTUnwrap(URL(string: "https://example.com/authorize"))
        let flow = AddAccountFlow(store: AccountStore(defaults: defaults, vault: InMemoryCredentialVault())) { _ in
            SlowBrowserLogin(url: url)
        }
        let presentation = SheetPresentation()
        let host = NSHostingView(rootView: SheetHost(presentation: presentation, flow: flow))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 500)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        addTeardownBlock {
            window.attachedSheet.map { window.endSheet($0) }
            window.close()
        }
        let sheet = try await waitForSheet(on: window)

        flow.choose(.codex)
        try await waitUntil { flow.prompt != nil }

        pressEscape(in: sheet)
        try await waitUntil { flow.provider == nil }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(flow.selection, .codex)
        XCTAssertNil(flow.prompt)
        XCTAssertFalse(flow.isWorking)
        XCTAssertTrue(presentation.isPresented)
        XCTAssertNotNil(window.attachedSheet, "Cancel on the sign-in step closed the sheet")

        pressEscape(in: sheet)
        try await waitUntil { !presentation.isPresented }
        XCTAssertFalse(presentation.isPresented, "Cancel on the provider list didn't close the sheet")
    }

    func testArrowKeysAndReturnChooseAProvider() async throws {
        let suite = "OpenUsageTests.AddAccountSheet.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let url = try XCTUnwrap(URL(string: "https://example.com/authorize"))
        let flow = AddAccountFlow(store: AccountStore(defaults: defaults, vault: InMemoryCredentialVault())) { _ in
            SlowBrowserLogin(url: url)
        }
        let presentation = SheetPresentation()
        let host = NSHostingView(rootView: SheetHost(presentation: presentation, flow: flow))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 700)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        addTeardownBlock {
            flow.cancel()
            window.attachedSheet.map { window.endSheet($0) }
            window.close()
        }
        let sheet = try await waitForSheet(on: window)

        press(keyCode: 125, character: "\u{F701}", in: sheet)
        press(keyCode: 125, character: "\u{F701}", in: sheet)
        try await waitUntil { flow.selection == .codex }
        XCTAssertNil(flow.provider, "Moving the selection must not choose the provider")

        press(keyCode: 36, character: "\r", in: sheet)
        try await waitUntil { flow.provider == .codex }
        XCTAssertEqual(flow.provider, .codex)
    }

    private func press(keyCode: UInt16, character: String, in sheet: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            sheet.sendEvent(NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: keyCode == 125 ? [.numericPad, .function] : [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: sheet.windowNumber, context: nil,
                characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: keyCode
            )!)
        }
    }

    private func waitForSheet(on window: NSWindow) async throws -> NSWindow {
        try await waitUntil { window.attachedSheet != nil }
        let sheet = try XCTUnwrap(window.attachedSheet)
        sheet.makeKey()
        try await Task.sleep(for: .milliseconds(300))
        return sheet
    }

    private func pressEscape(in sheet: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            sheet.sendEvent(NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: sheet.windowNumber, context: nil, characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53
            )!)
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "Timed out waiting for the Add Account sheet")
    }
}

@MainActor
@Observable
private final class SheetPresentation {
    var isPresented = true
}

private struct SheetHost: View {
    @Bindable var presentation: SheetPresentation
    let flow: AddAccountFlow

    var body: some View {
        Color.clear
            .sheet(isPresented: $presentation.isPresented) {
                AddAccountSheet(flow: flow)
            }
    }
}

private struct SlowBrowserLogin: ProviderLogin {
    let url: URL

    func login(prompt show: @Sendable (LoginPrompt) async -> Void, pastedCode: AsyncStream<String>) async throws -> (label: String, credential: AccountCredential) {
        await show(.browser(url, acceptsPastedCode: false))
        try await Task.sleep(for: .seconds(30))
        return ("late", .oauth(OAuthTokens(accessToken: "access")))
    }
}

import AppKit
import SwiftUI
import XCTest
@testable import OpenUsage

/// The dashboard shows what it shows: nothing on a provider's header, a caption or a row opens on a
/// click, no plan or name reacts to the pointer, a plan is plain text and never a badge, and a row under
/// the pointer draws exactly as it does at rest. Three things react: resting the pointer on a row opens
/// the account's resets after the hover dwell, a double-click on an account's name renames it, on its
/// caption or in a one-account provider's header, and the logo turns into the copy button while the
/// pointer is on the provider. Dragging still reorders: the header drags the provider, a caption drags
/// its account, and a row drags itself.
@MainActor
final class DashboardSectionTests: QuietWindowTestCase {
    private final class Log {
        var accountDrags = 0
        var metricDrags = 0
        var headerDrags = 0
    }

    /// The hosted section, with the account a rename can begin on.
    private struct Hosted {
        let window: NSWindow
        let host: NSView
        let renaming: AccountRenameStore
        let accountID: String
    }

    /// The caption's centre line, inside the card under the header.
    private static let captionY = DashboardGrid.headerHeight + DashboardGrid.headerGap + DashboardGrid.cardPadding + DashboardGrid.captionHeight / 2
    /// The first row's centre line, under the caption.
    private static let firstRowY = DashboardGrid.headerHeight + DashboardGrid.headerGap + DashboardGrid.cardPadding
        + DashboardGrid.captionHeight + DashboardGrid.rowHeight / 2
    /// A point on a name that starts 12 pt in.
    private static let nameX = DashboardGrid.cardPadding + DashboardGrid.inset + 10

    private let lines: [DashboardLine] = ["Session", "Weekly", "Fable"].map { title in
        var data = WidgetData(title: title, icon: .providerMark("claude"), kind: .percent, used: 30, limit: 100)
        data.resetsAt = Date().addingTimeInterval(3 * 3600)
        data.periodDurationMs = 5 * 3600 * 1000
        return DashboardLine(descriptor: WidgetDescriptor(id: title, providerID: "claude", metricLabel: title, sample: data), data: data)
    }

    private let work = Provider(id: "claude@2", displayName: "Claude", icon: .providerMark("claude"), accountLabel: "Work")

    private func account(_ provider: Provider) -> DashboardAccount {
        DashboardAccount(provider: provider, lines: lines)
    }

    /// SwiftUI names every modifier and control in a view's body type: `_HoverRegionModifier` for
    /// `onHover`, `TapGesture` for `onTapGesture`, `Button`, and this app's `HoverTooltipModifier`.
    private static let interactive = ["Hover", "TapGesture", "Button", "Popover", "Tooltip", "Help"]

    private func interactiveParts(_ body: some View) -> [String] {
        let type = String(reflecting: Swift.type(of: body))
        return Self.interactive.filter { type.contains($0) }
    }

    func testTheDetectorSeesHoverAndTapHandlers() {
        XCTAssertEqual(interactiveParts(Text("x").onHover { _ in }), ["Hover"])
        XCTAssertEqual(interactiveParts(Text("x").onContinuousHover { _ in }), ["Hover"])
        XCTAssertEqual(interactiveParts(Text("x").onTapGesture {}), ["TapGesture"])
        XCTAssertEqual(interactiveParts(Button("x") {}), ["Button"])
        XCTAssertFalse(interactiveParts(Text("x").hoverTooltip("y")).isEmpty)
        XCTAssertFalse(interactiveParts(Text("x").help("y")).isEmpty)
    }

    func testOnlyTheLiveRowTheNameAndTheCopyButtonReact() {
        let personal = account(Provider(id: "claude@1", displayName: "Claude", icon: .providerMark("claude"), accountLabel: "Personal"))
        let family = DashboardFamily(id: "claude", provider: personal.provider, accounts: [personal, account(work)])
        let section = DashboardProviderSection(family: family, plans: ["claude@1": "Max 5x"], status: AccountStatus(notice: "Refresh failed")) {
            ProviderIcon(source: family.provider.icon, inset: 0.04)
        } account: { account in
            DashboardAccountRows(account: account, plan: "Max 5x")
        }
        var credits = WidgetData(title: "Extra Usage", icon: .providerMark("codex"), kind: .count, used: 452, limit: nil)
        credits.values = [MetricValue(number: 452, kind: .count, label: "credits")]
        let stale = DashboardAccountCaption(account: personal, plan: "Max 5x", status: AccountStatus(staleness: StalenessHint(label: "1h ago", tooltip: "Last updated 1 hour ago")))

        XCTAssertEqual(interactiveParts(section.body), [], "section")
        XCTAssertEqual(interactiveParts(section.header), [], "header")
        XCTAssertEqual(interactiveParts(DashboardAccountCaption(account: personal, plan: "Max 5x").body), [], "caption")
        XCTAssertEqual(interactiveParts(stale.body), [], "stale caption")
        XCTAssertEqual(interactiveParts(AccountStatus(notice: "Refresh failed").glyph), [], "status glyph")
        // The name's one handler is the double-click (`onTapGesture(count: 2)`); the tests below prove
        // a single click there does nothing.
        XCTAssertEqual(interactiveParts(AccountName(account: personal, font: .body).body), ["TapGesture"], "name")
        XCTAssertEqual(interactiveParts(DashboardMetricRow(model: lines[0].data.dashboardRow()).body), [], "row")
        XCTAssertEqual(interactiveParts(DashboardMetricRow(model: credits.dashboardRow()).body), [], "value row")
        XCTAssertEqual(interactiveParts(DashboardHoverRow(line: lines[0], account: personal).body), ["Hover", "Popover"], "live row")
        XCTAssertEqual(interactiveParts(DashboardCopyButton(provider: personal.provider, active: true, copy: { true }).body), ["Hover", "Button", "Tooltip"], "copy button")
    }

    /// Resting the pointer on a row opens the account's resets after the hover dwell, with no click,
    /// and changes nothing on the panel itself: no highlight, no text swap, no height; resting it on the
    /// caption's name opens nothing.
    func testHoveringARowOpensTheAccountsResetsAndDrawsTheRowAsAtRest() throws {
        let log = Log()
        let hosted = hostWithRenaming(log: log)
        let shown = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
        func popoverIsOpen() -> Bool { NSApp.windows.contains { $0.isVisible && !shown.contains(ObjectIdentifier($0)) } }
        let height = hosted.host.fittingSize.height
        let atRest = try pixels(of: hosted.host)

        try hover(CGPoint(x: Self.nameX, y: Self.captionY), hosted.window, hosted.host)
        XCTAssertFalse(popoverIsOpen(), "hovering the name opens something")

        try hover(CGPoint(x: hosted.host.bounds.width / 2, y: Self.firstRowY), hosted.window, hosted.host)
        XCTAssertTrue(popoverIsOpen(), "hovering a row opens no popover")
        XCTAssertEqual(hosted.host.fittingSize.height, height, "the hover changed the height")
        XCTAssertEqual(try pixels(of: hosted.host), atRest, "the row under the pointer draws differently from the row at rest")
        XCTAssertEqual(log.accountDrags + log.metricDrags, 0)
        HoverPopoverState.dismissAll()
    }

    /// A plan is plain secondary text, in the header and on a caption alike: no capsule, no plate.
    func testAPlanIsNeverABadge() {
        let personal = account(Provider(id: "claude@1", displayName: "Claude", icon: .providerMark("claude"), accountLabel: "Personal"))
        let family = DashboardFamily(id: "claude", provider: personal.provider, accounts: [personal])
        let header = DashboardProviderHeader(family: family, plan: "Max 20x") { EmptyView() }
        for (name, body) in [("header", String(reflecting: type(of: header.body))),
                             ("caption", String(reflecting: type(of: DashboardAccountCaption(account: personal, plan: "Max 20x").body)))] {
            for badge in ["Capsule", "Background", "RoundedRectangle"] {
                XCTAssertFalse(body.contains(badge), "the \(name) draws its plan with a \(badge)")
            }
        }
    }

    /// The host's pixels as drawn now.
    private func pixels(of host: NSView) throws -> Data {
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    /// A click on an account's name, on its plan or on a row opens nothing, starts no drag and no rename.
    func testClicksChangeNothing() throws {
        let log = Log()
        let hosted = hostWithRenaming(log: log)
        let shown = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
        let points = [
            CGPoint(x: Self.nameX, y: Self.captionY),
            CGPoint(x: hosted.host.bounds.width - DashboardGrid.cardPadding - DashboardGrid.inset - 12, y: Self.captionY),
            CGPoint(x: hosted.host.bounds.width / 2, y: Self.firstRowY),
        ]
        for point in points {
            send(.mouseMoved, at: point, hosted.window, hosted.host)
            send(.leftMouseDown, at: point, hosted.window, hosted.host)
            send(.leftMouseUp, at: point, hosted.window, hosted.host)
            XCTAssertFalse(NSApp.windows.contains { $0.isVisible && !shown.contains(ObjectIdentifier($0)) }, "a click at \(point) opened a window")
            // Off the row before its hover dwell runs out.
            send(.mouseMoved, at: CGPoint(x: hosted.host.bounds.width / 2, y: DashboardGrid.headerHeight / 2), hosted.window, hosted.host)
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        }
        XCTAssertEqual(log.accountDrags + log.metricDrags, 0)
        XCTAssertNil(hosted.renaming.edit, "a click started a rename")
    }

    func testTheCaptionDragsTheAccountAndARowDragsItself() {
        let log = Log()
        let hosted = hostWithRenaming(log: log)
        // The empty middle of the caption belongs to it too.
        drag(from: CGPoint(x: hosted.host.bounds.width / 2, y: Self.captionY), hosted.window, hosted.host)
        XCTAssertGreaterThan(log.accountDrags, 0)
        XCTAssertEqual(log.metricDrags, 0)

        log.accountDrags = 0
        drag(from: CGPoint(x: hosted.host.bounds.width / 2, y: Self.firstRowY), hosted.window, hosted.host)
        XCTAssertGreaterThan(log.metricDrags, 0)
        XCTAssertEqual(log.accountDrags, 0)
    }

    /// A double-click on the account's name opens the inline rename, as the right-click Rename does. A
    /// single click there, or a double-click on the empty rest of the caption, does nothing.
    func testDoubleClickingTheNameRenamesTheAccountAndASingleClickDoesNot() throws {
        let log = Log()
        let hosted = hostWithRenaming(log: log)
        let name = CGPoint(x: Self.nameX, y: Self.captionY)

        click(name, hosted.window, hosted.host)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        XCTAssertNil(hosted.renaming.edit, "a single click on the name starts a rename")

        doubleClick(CGPoint(x: hosted.host.bounds.width / 2, y: name.y), hosted.window, hosted.host)
        XCTAssertNil(hosted.renaming.edit, "a double-click beside the name starts a rename")

        doubleClick(name, hosted.window, hosted.host)
        XCTAssertTrue(hosted.renaming.isRenaming(hosted.accountID), "a double-click on the name opens no rename")
        XCTAssertEqual(hosted.renaming.draft, "Personal")
        try assertWholeNameSelected("Personal", in: hosted.window)
        XCTAssertEqual(log.accountDrags + log.metricDrags, 0)
    }

    /// A one-account provider shows no caption: its header reads "Claude — Work". A double-click on
    /// the name there renames the account in place with the whole name selected; a single click does
    /// nothing; the header drags the provider.
    func testAOneAccountHeaderNamesTheAccountAndRenamesIt() throws {
        let log = Log()
        let (renaming, provider) = storedAccount(label: "Work")
        let family = DashboardFamily(id: "claude", provider: provider, accounts: [account(provider)])
        let section = DashboardProviderSection(
            family: family, plans: [provider.id: "Max 5x"],
            handle: { AnyView($0.highPriorityGesture(DragGesture(minimumDistance: 4).onChanged { _ in log.headerDrags += 1 })) }
        ) {
            ProviderIcon(source: provider.icon, inset: 0.04)
        } account: { account in
            DashboardAccountRows(account: account, showsCaption: false)
        }
        let (window, host) = hostView(section, renaming: renaming)

        XCTAssertEqual(
            host.fittingSize.height,
            DashboardGrid.headerHeight + DashboardGrid.headerGap + 2 * DashboardGrid.cardPadding + 3 * DashboardGrid.rowHeight,
            accuracy: 1,
            "a header and a card of three rows, with no caption"
        )

        let headerMid = DashboardGrid.headerHeight / 2
        let font = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .title3).pointSize, weight: .semibold)
        let name = CGPoint(x: Self.nameX + ("Claude — " as NSString).size(withAttributes: [.font: font]).width, y: headerMid)
        click(name, window, host)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        XCTAssertNil(renaming.edit, "a single click on the name starts a rename")

        doubleClick(name, window, host)
        XCTAssertTrue(renaming.isRenaming(provider.id), "a double-click on the header's name opens no rename")
        XCTAssertEqual(renaming.draft, "Work")
        try assertWholeNameSelected("Work", in: window)
        renaming.cancel()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        drag(from: CGPoint(x: host.bounds.width / 2, y: headerMid), window, host)
        XCTAssertGreaterThan(log.headerDrags, 0, "the header doesn't drag the provider")
        XCTAssertNil(renaming.edit)
    }

    /// Right-click → Rename starts the same edit, and it too opens with the whole name selected.
    func testARenameFromTheMenuSelectsTheWholeName() throws {
        let hosted = hostWithRenaming(log: Log())
        hosted.renaming.begin(hosted.accountID)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        try assertWholeNameSelected("Personal", in: hosted.window)
    }

    private func assertWholeNameSelected(_ name: String, in window: NSWindow, line: UInt = #line) throws {
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView, "the rename field doesn't take focus", line: line)
        XCTAssertEqual(editor.string, name, line: line)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: (name as NSString).length), "the whole name isn't selected", line: line)
    }

    /// Pressing on the name and moving lifts the account on the first move, with no wait for a second
    /// click, and opens no rename.
    func testDraggingTheNameDragsTheAccountAtOnce() {
        let log = Log()
        let hosted = hostWithRenaming(log: log)
        let name = CGPoint(x: Self.nameX, y: Self.captionY)

        send(.leftMouseDown, at: name, hosted.window, hosted.host)
        send(.leftMouseDragged, at: CGPoint(x: name.x, y: name.y + 12), hosted.window, hosted.host)
        XCTAssertGreaterThan(log.accountDrags, 0, "the drag waited past the first move")
        send(.leftMouseUp, at: CGPoint(x: name.x, y: name.y + 12), hosted.window, hosted.host)

        // A second press-and-drag right after, which reads as the second click of a double-click, drags too.
        log.accountDrags = 0
        send(.leftMouseDown, at: name, hosted.window, hosted.host, clickCount: 2)
        send(.leftMouseDragged, at: CGPoint(x: name.x, y: name.y + 12), hosted.window, hosted.host, clickCount: 2)
        XCTAssertGreaterThan(log.accountDrags, 0, "a drag on the second click didn't lift the account")
        send(.leftMouseUp, at: CGPoint(x: name.x, y: name.y + 12), hosted.window, hosted.host, clickCount: 2)

        XCTAssertEqual(log.metricDrags, 0)
        XCTAssertNil(hosted.renaming.edit, "a drag on the name started a rename")
    }

    /// A Claude account saved under `label`, and a rename store that can edit it.
    private func storedAccount(label: String) -> (AccountRenameStore, Provider) {
        let name = "OpenUsageTests.DashboardSection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let accounts = AccountStore(defaults: defaults, vault: InMemoryCredentialVault())
        let stored = accounts.add(kind: .claude, label: label, credential: .apiKey("key"))
        let provider = Provider(id: stored.cardID, displayName: "Claude", icon: .providerMark("claude"), accountLabel: label)
        return (AccountRenameStore(accounts: accounts), provider)
    }

    /// A provider with two accounts, Personal (saved, so it can be renamed) and Work, as the dashboard
    /// hosts it: each caption carries its account's drag, every row its own hover and drag, and the
    /// environment holds the rename store.
    private func hostWithRenaming(log: Log) -> Hosted {
        let (renaming, provider) = storedAccount(label: "Personal")
        let family = DashboardFamily(id: "claude", provider: provider, accounts: [account(provider), account(work)])
        let view = DashboardProviderSection(family: family) {
            ProviderIcon(source: provider.icon, inset: 0.04)
        } account: { account in
            VStack(alignment: .leading, spacing: 0) {
                DashboardAccountCaption(account: account, plan: "Max 5x")
                    .highPriorityGesture(DragGesture(minimumDistance: 4).onChanged { _ in log.accountDrags += 1 })
                ForEach(account.lines) { line in
                    DashboardHoverRow(line: line, account: account)
                        .highPriorityGesture(DragGesture(minimumDistance: 4).onChanged { _ in log.metricDrags += 1 })
                }
            }
        }
        let (window, host) = hostView(view, renaming: renaming)
        return Hosted(window: window, host: host, renaming: renaming, accountID: provider.id)
    }

    /// `view` at the card's width in an offscreen window that takes events, with `renaming` in its
    /// environment.
    private func hostView(_ content: some View, renaming: AccountRenameStore) -> (NSWindow, NSView) {
        let view = content
            .frame(width: PanelMetrics.width - 2 * PanelMetrics.margin)
            .environment(renaming)
            .environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        // The dashboard's own panel, so clicks and the rename field behave as in the app, minus the
        // keyboard: it never becomes key.
        let window = QuietMenuBarPanel(contentRect: host.frame)
        window.acceptsMouseMovedEvents = true
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        QuietTestProcess.show(window, in: self)
        host.layoutSubtreeIfNeeded()
        return (window, host)
    }

    /// Moves the pointer onto `point` and rests there past the popover's 400 ms hover dwell. The real
    /// pointer never reaches an offscreen window, so this delivers what AppKit would: the enter event
    /// for the host's tracking area, then a move to `point`.
    private func hover(_ point: CGPoint, _ window: NSWindow, _ host: NSView) throws {
        let area = try XCTUnwrap(host.trackingAreas.first, "nothing on the section tracks the pointer")
        host.mouseEntered(with: NSEvent.enterExitEvent(
            with: .mouseEntered,
            location: NSPoint(x: point.x, y: host.bounds.height - point.y),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            trackingNumber: Int(bitPattern: Unmanaged.passUnretained(area).toOpaque()),
            userData: nil
        )!)
        send(.mouseMoved, at: point, window, host)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
    }

    private func click(_ point: CGPoint, _ window: NSWindow, _ host: NSView) {
        send(.mouseMoved, at: point, window, host)
        send(.leftMouseDown, at: point, window, host)
        send(.leftMouseUp, at: point, window, host)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    }

    private func doubleClick(_ point: CGPoint, _ window: NSWindow, _ host: NSView) {
        send(.mouseMoved, at: point, window, host)
        send(.leftMouseDown, at: point, window, host)
        send(.leftMouseUp, at: point, window, host)
        send(.leftMouseDown, at: point, window, host, clickCount: 2)
        send(.leftMouseUp, at: point, window, host, clickCount: 2)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
    }

    private func drag(from start: CGPoint, _ window: NSWindow, _ host: NSView) {
        let end = CGPoint(x: start.x, y: start.y + 12)
        send(.leftMouseDown, at: start, window, host)
        send(.leftMouseDragged, at: end, window, host)
        send(.leftMouseUp, at: end, window, host)
    }

    /// `point` is top-left based, in the host's coordinates.
    private func send(_ type: NSEvent.EventType, at point: CGPoint, _ window: NSWindow, _ host: NSView, clickCount: Int = 1) {
        let event = NSEvent.mouseEvent(
            with: type,
            location: NSPoint(x: point.x, y: host.bounds.height - point.y),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: type == .mouseMoved ? 0 : clickCount,
            pressure: type == .leftMouseDown || type == .leftMouseDragged ? 1 : 0
        )!
        window.sendEvent(event)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}

import AppKit
import SwiftUI
import XCTest
@testable import OpenUsage

/// The dashboard shows what it shows: no part of a card, an account, a metric line, or the plan tag
/// reacts to hover or a click. Two exceptions: hovering the ↺ tag opens the resets popover, and a
/// double-click on an account's name renames it, on its account line or in a one-account card's header.
/// Dragging still reorders: a card's header drags the card, the name line drags its account, and a
/// metric line drags itself.
@MainActor
final class DashboardAccountSectionTests: XCTestCase {
    private final class Log {
        var accountDrags = 0
        var metricDrags = 0
        var cardDrags = 0
    }

    /// The account the hosted section shows, saved so a rename can begin on it.
    private struct Hosted {
        let window: NSWindow
        let host: NSView
        let renaming: AccountRenameStore
        let accountID: String
    }

    private let account: DashboardAccount = {
        let lines = ["Session", "Weekly", "Fable"].map { title in
            let data = WidgetData(title: title, icon: .providerMark("claude"), kind: .percent, used: 30, limit: 100)
            return DashboardLine(descriptor: WidgetDescriptor(id: title, providerID: "claude", metricLabel: title, sample: data), data: data)
        }
        var resets = WidgetData(title: "Rate Limit Resets", icon: .providerMark("claude"), kind: .count, used: 2, limit: nil)
        resets.values = [MetricValue(number: 2, kind: .count, label: "available")]
        resets.showsResetExpiries = true
        resets.expiriesAt = [Date().addingTimeInterval(9 * 86_400)]
        return DashboardAccount(
            provider: Provider(id: "claude@1", displayName: "Claude", icon: .providerMark("claude"), accountLabel: "Personal"),
            lines: lines,
            resets: resets
        )
    }()

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

    func testOnlyTheResetsTagHasAHoverOrTapHandler() {
        let section = DashboardAccountSection(
            account: account, badges: AccountBadges(resets: account.resets, plan: "Max 5x", notice: "Refresh failed")
        ) {
            DashboardMetricLine(data: $0.data)
        }
        let stale = DashboardAccountSection(
            account: account,
            badges: AccountBadges(plan: "Max 5x", staleness: StalenessHint(label: "1h ago", tooltip: "Last updated 1 hour ago"))
        ) { _ in EmptyView() }
        let headerless = DashboardAccountSection(account: account, showsAccountLine: false) { DashboardMetricLine(data: $0.data) }
        let other = DashboardAccount(provider: Provider(id: "claude@2", displayName: "Claude", icon: .providerMark("claude")), lines: [])
        let card = DashboardProviderCard(family: DashboardFamily(id: "claude", provider: account.provider, accounts: [account, other])) { _ in
            EmptyView()
        }
        let soleCard = DashboardProviderCard(
            family: DashboardFamily(id: "claude", provider: account.provider, accounts: [account]),
            badges: { AccountBadges(resets: $0.resets, plan: "Max 5x", notice: "Refresh failed") }
        ) { _ in EmptyView() }
        var credits = WidgetData(title: "Extra Usage", icon: .providerMark("codex"), kind: .count, used: 452, limit: nil)
        credits.values = [MetricValue(number: 452, kind: .count, label: "credits")]
        var weekly = account.lines[1].data
        weekly.resetsAt = Date().addingTimeInterval(86_400)

        XCTAssertEqual(interactiveParts(section.body), [], "account")
        // The account line's one handler is the double-click on its name (`onTapGesture(count: 2)`);
        // the tests below prove a single click there does nothing.
        XCTAssertEqual(interactiveParts(section.accountLine), [], "account line")
        XCTAssertEqual(interactiveParts(section.name.body), ["TapGesture"], "account name")
        XCTAssertEqual(interactiveParts(stale.body), [], "stale account")
        XCTAssertEqual(interactiveParts(headerless.body), [], "account on a one-account card")
        XCTAssertEqual(interactiveParts(card.body), [], "provider card")
        XCTAssertEqual(interactiveParts(card.header), [], "provider card header")
        // A one-account card's header holds the account's name, whose double-click renames it, and the
        // ↺ tag; nothing else in it reacts.
        XCTAssertEqual(interactiveParts(soleCard.header), [], "one-account card header")
        XCTAssertEqual(interactiveParts(DashboardMetricLine(data: weekly).body), [], "metric line")
        XCTAssertEqual(interactiveParts(DashboardMetricLine(data: credits).body), [], "metric line without a limit")
        XCTAssertEqual(interactiveParts(PlanTag(plan: "Max 5x").body), [], "plan tag")
        XCTAssertEqual(interactiveParts(ResetCountChip(data: account.resets!).body), ["Hover", "Button", "Popover"], "resets tag")
    }

    /// Resting the pointer on the ↺ tag opens the resets popover after the hover dwell, with no click.
    func testHoveringTheResetsTagOpensItsPopover() throws {
        let log = Log()
        let (window, host) = host(log: log)
        let shown = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
        func popoverIsOpen() -> Bool { NSApp.windows.contains { $0.isVisible && !shown.contains(ObjectIdentifier($0)) } }
        let nameLine = DashboardBox.accountPadding + DashboardAccountSection<EmptyView>.lineHeight / 2

        try hover(CGPoint(x: DashboardBox.inset + 10, y: nameLine), window, host)
        XCTAssertFalse(popoverIsOpen(), "hovering the name opens nothing")

        try hover(Self.resetsTag(in: host), window, host)
        XCTAssertTrue(popoverIsOpen(), "hovering the ↺ tag opens the resets popover")
        XCTAssertEqual(log.accountDrags + log.metricDrags, 0)
        HoverPopoverState.dismissAll()
    }

    /// A click anywhere on an account but the ↺ tag (its name, the plan tag, a metric's value) opens
    /// nothing, starts no drag, and changes nothing on screen.
    func testClicksChangeNothing() throws {
        let log = Log()
        let (window, host) = host(log: log)
        let before = try pixels(host)
        let shown = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
        let nameLine = DashboardBox.accountPadding + DashboardAccountSection<EmptyView>.lineHeight / 2
        let firstMetric = DashboardBox.accountPadding + DashboardAccountSection<EmptyView>.lineHeight + DashboardMetricLine.height / 2
        let points = [
            CGPoint(x: DashboardBox.inset + 10, y: nameLine),
            CGPoint(x: host.bounds.width - DashboardBox.inset - 20, y: nameLine),
            CGPoint(x: host.bounds.width - DashboardBox.inset - 80, y: firstMetric),
        ]
        for point in points {
            click(point, window, host)
        }
        XCTAssertFalse(NSApp.windows.contains { $0.isVisible && !shown.contains(ObjectIdentifier($0)) }, "a click opened a window")
        XCTAssertEqual(log.accountDrags + log.metricDrags, 0)
        XCTAssertEqual(try pixels(host), before, "a click changed what the account shows")
    }

    func testTheNameLineDragsTheAccountAndAMetricLineDragsItself() {
        let log = Log()
        let (window, host) = host(log: log)
        let nameLine = DashboardBox.accountPadding + DashboardAccountSection<EmptyView>.lineHeight / 2
        // The empty middle of the name line belongs to it too.
        drag(from: CGPoint(x: host.bounds.width / 2, y: nameLine), window, host)
        XCTAssertGreaterThan(log.accountDrags, 0)
        XCTAssertEqual(log.metricDrags, 0)

        log.accountDrags = 0
        let firstMetric = DashboardBox.accountPadding + DashboardAccountSection<EmptyView>.lineHeight + DashboardMetricLine.height / 2
        drag(from: CGPoint(x: host.bounds.width / 2, y: firstMetric), window, host)
        XCTAssertGreaterThan(log.metricDrags, 0)
        XCTAssertEqual(log.accountDrags, 0)
    }

    /// A double-click on the account's name opens the inline rename, as the right-click Rename does. A
    /// single click there, or a double-click on the empty rest of the name line, does nothing.
    func testDoubleClickingTheNameRenamesTheAccountAndASingleClickDoesNot() throws {
        let log = Log()
        let hosted = hostWithRenaming(log: log)
        let name = Self.name(in: hosted.host)

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

    /// A card with one account shows no account line below its header. A double-click on the name in
    /// the header renames the account in place with the whole name selected; a single click does
    /// nothing; the header drags the card.
    func testAOneAccountCardsHeaderShowsTheAccountsNameAndRenamesIt() throws {
        let log = Log()
        let (renaming, provider) = storedAccount(label: "Work")
        let sole = DashboardAccount(provider: provider, lines: account.lines, resets: account.resets)
        let card = DashboardProviderCard(
            family: DashboardFamily(id: "claude", provider: provider, accounts: [sole]),
            badges: { AccountBadges(resets: $0.resets, plan: "Max 5x") },
            handle: { AnyView($0.highPriorityGesture(DragGesture(minimumDistance: 4).onChanged { _ in log.cardDrags += 1 })) }
        ) {
            DashboardAccountSection(account: $0, showsAccountLine: false) { DashboardMetricLine(data: $0.data) }
        }
        let (window, host) = hostView(card, renaming: renaming)

        XCTAssertEqual(
            host.fittingSize.height,
            DashboardBox.topPadding + 18 + DashboardBox.headerGap + 2 * DashboardBox.accountPadding
                + 3 * DashboardMetricLine.height + DashboardBox.bottomPadding,
            accuracy: 1,
            "a header and three metric lines, with no account line"
        )

        // The name follows the 16 pt mark and its 6 pt gap.
        let headerMid = DashboardBox.topPadding + 9
        let name = CGPoint(x: DashboardBox.inset + 16 + 6 + 10, y: headerMid)
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
        XCTAssertGreaterThan(log.cardDrags, 0, "the header doesn't drag the card")
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
        let name = Self.name(in: hosted.host)

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

    private func host(log: Log) -> (NSWindow, NSView) {
        let hosted = hostWithRenaming(log: log)
        return (hosted.window, hosted.host)
    }

    /// A Claude account saved under `label`, and a rename store that can edit it.
    private func storedAccount(label: String) -> (AccountRenameStore, Provider) {
        let name = "OpenUsageTests.DashboardAccountSection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let accounts = AccountStore(defaults: defaults, vault: InMemoryCredentialVault())
        let stored = accounts.add(kind: .claude, label: label, credential: .apiKey("key"))
        let provider = Provider(id: stored.cardID, displayName: "Claude", icon: .providerMark("claude"), accountLabel: label)
        return (AccountRenameStore(accounts: accounts), provider)
    }

    /// The section as the dashboard hosts it: the name line carries the account's drag, every metric
    /// line its own, and the environment holds the rename store with the account saved in it.
    private func hostWithRenaming(log: Log) -> Hosted {
        let (renaming, provider) = storedAccount(label: "Personal")
        let shown = DashboardAccount(provider: provider, lines: account.lines, resets: account.resets)
        let view = DashboardAccountSection(
            account: shown,
            badges: AccountBadges(resets: shown.resets, plan: "Max 5x"),
            handle: { AnyView($0.highPriorityGesture(DragGesture(minimumDistance: 4).onChanged { _ in log.accountDrags += 1 })) }
        ) { line in
            // As the dashboard wires it: every metric line carries its own drag.
            DashboardMetricLine(data: line.data)
                .contentShape(Rectangle())
                .highPriorityGesture(DragGesture(minimumDistance: 4).onChanged { _ in log.metricDrags += 1 })
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
        // The dashboard's own key-capable panel, so a rename field edits as it does in the app.
        let window = MenuBarPanel(contentRect: host.frame)
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        // Off every screen: the window must be ordered in to take events, never seen.
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        addTeardownBlock { window.close() }
        return (window, host)
    }

    /// A point on the account's name, at the leading edge of the name line.
    private static func name(in host: NSView) -> CGPoint {
        CGPoint(x: DashboardBox.inset + 10, y: DashboardBox.accountPadding + DashboardAccountSection<EmptyView>.lineHeight / 2)
    }

    /// The ↺ tag's center: it sits just before the plan tag at the account line's trailing edge.
    private static func resetsTag(in host: NSView) -> CGPoint {
        CGPoint(
            x: host.bounds.width - DashboardBox.inset - 80,
            y: DashboardBox.accountPadding + DashboardAccountSection<EmptyView>.lineHeight / 2
        )
    }

    /// Moves the pointer onto `point` and rests there past the popover's 400 ms hover dwell. The real
    /// pointer never reaches an offscreen window, so this delivers what AppKit would: the enter event
    /// for the host's tracking area, then a move to `point`.
    private func hover(_ point: CGPoint, _ window: NSWindow, _ host: NSView) throws {
        let area = try XCTUnwrap(host.trackingAreas.first, "nothing on the account tracks the pointer")
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

    private func pixels(_ host: NSView) throws -> Data {
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
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

import AppKit
import SwiftUI
import XCTest
@testable import OpenUsage

/// The dashboard shows what it shows: no part of a card, an account, a metric line, or its tags reacts
/// to hover or a click. Dragging still reorders: the name line drags its account and a metric line
/// drags itself.
@MainActor
final class DashboardAccountSectionTests: XCTestCase {
    private final class Log {
        var accountDrags = 0
        var metricDrags = 0
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

    func testNoDashboardViewHasAHoverOrTapHandler() {
        let section = DashboardAccountSection(account: account, plan: "Max 5x", notice: "Refresh failed") {
            DashboardMetricLine(data: $0.data)
        }
        let stale = DashboardAccountSection(
            account: account, plan: "Max 5x", staleness: StalenessHint(label: "1h ago", tooltip: "Last updated 1 hour ago")
        ) { _ in EmptyView() }
        let card = DashboardProviderCard(family: DashboardFamily(id: "claude", provider: account.provider, accounts: [account])) { _ in
            EmptyView()
        }
        var credits = WidgetData(title: "Extra Usage", icon: .providerMark("codex"), kind: .count, used: 452, limit: nil)
        credits.values = [MetricValue(number: 452, kind: .count, label: "credits")]
        var weekly = account.lines[1].data
        weekly.resetsAt = Date().addingTimeInterval(86_400)

        XCTAssertEqual(interactiveParts(section.body), [], "account")
        XCTAssertEqual(interactiveParts(stale.body), [], "stale account")
        XCTAssertEqual(interactiveParts(card.body), [], "provider card")
        XCTAssertEqual(interactiveParts(DashboardMetricLine(data: weekly).body), [], "metric line")
        XCTAssertEqual(interactiveParts(DashboardMetricLine(data: credits).body), [], "metric line without a limit")
        XCTAssertEqual(interactiveParts(ResetCountTag(data: account.resets!).body), [], "resets tag")
        XCTAssertEqual(interactiveParts(PlanTag(plan: "Max 5x").body), [], "plan tag")
    }

    /// A click anywhere on an account (its name, the ↺ tag, the plan tag, a metric's value) opens
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
            CGPoint(x: host.bounds.width - DashboardBox.inset - 80, y: nameLine),
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

    private func host(log: Log) -> (NSWindow, NSView) {
        let view = DashboardAccountSection(
            account: account,
            plan: "Max 5x",
            handle: { AnyView($0.highPriorityGesture(DragGesture(minimumDistance: 4).onChanged { _ in log.accountDrags += 1 })) }
        ) { line in
            // As the dashboard wires it: every metric line carries its own drag.
            DashboardMetricLine(data: line.data)
                .contentShape(Rectangle())
                .highPriorityGesture(DragGesture(minimumDistance: 4).onChanged { _ in log.metricDrags += 1 })
        }
        .frame(width: 292)
        .environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        // Off every screen: the window must be ordered in to take events, never seen.
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        addTeardownBlock { window.close() }
        return (window, host)
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

    private func drag(from start: CGPoint, _ window: NSWindow, _ host: NSView) {
        let end = CGPoint(x: start.x, y: start.y + 12)
        send(.leftMouseDown, at: start, window, host)
        send(.leftMouseDragged, at: end, window, host)
        send(.leftMouseUp, at: end, window, host)
    }

    /// `point` is top-left based, in the host's coordinates.
    private func send(_ type: NSEvent.EventType, at point: CGPoint, _ window: NSWindow, _ host: NSView) {
        let event = NSEvent.mouseEvent(
            with: type,
            location: NSPoint(x: point.x, y: host.bounds.height - point.y),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: type == .mouseMoved ? 0 : 1,
            pressure: type == .leftMouseDown || type == .leftMouseDragged ? 1 : 0
        )!
        window.sendEvent(event)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}

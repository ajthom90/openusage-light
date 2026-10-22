import AppKit
import SwiftUI
import XCTest
@testable import OpenUsage

/// The whole account block is one click target, collapsed or expanded: header, metric lines, padding,
/// and empty space all toggle it. A drag on it stays a drag, and a click on the Resets value opens the
/// resets timeline instead of toggling the account.
@MainActor
final class DashboardAccountRowClickTests: XCTestCase {
    private final class Log {
        var toggles = 0
        var drags = 0
    }

    private let account: DashboardAccount = {
        var lines = ["Session", "Weekly", "Fable"].map { title in
            let data = WidgetData(title: title, icon: .providerMark("claude"), kind: .percent, used: 30, limit: 100)
            return DashboardLine(descriptor: WidgetDescriptor(id: title, providerID: "claude", metricLabel: title, sample: data), data: data)
        }
        var resets = WidgetData(title: "Rate Limit Resets", icon: .providerMark("claude"), kind: .count, used: 2, limit: nil)
        resets.values = [MetricValue(number: 2, kind: .count, label: "available")]
        resets.showsResetExpiries = true
        resets.expiriesAt = [Date().addingTimeInterval(9 * 86_400)]
        lines.append(DashboardLine(descriptor: WidgetDescriptor(id: "resets", providerID: "claude", metricLabel: "Rate Limit Resets", sample: resets), data: resets))
        return DashboardAccount(
            provider: Provider(id: "claude@1", displayName: "Claude", icon: .providerMark("claude"), accountLabel: "Personal"),
            lines: lines
        )
    }()

    func testClickAnywhereOnTheCollapsedBlockToggles() {
        let log = Log()
        let (window, host) = host(expanded: false, log: log)
        let size = host.bounds.size
        for point in [CGPoint(x: 1, y: 1), CGPoint(x: size.width / 2, y: size.height / 2), CGPoint(x: size.width - 1, y: size.height - 1)] {
            click(point, window, host)
        }
        XCTAssertEqual(log.toggles, 3)
    }

    func testClickOnAnExpandedLineCollapsesLikeTheHeader() {
        let log = Log()
        let (window, host) = host(expanded: true, log: log)
        let row = DashboardMetricLine.height
        click(CGPoint(x: host.bounds.width / 2, y: row / 2), window, host)
        click(CGPoint(x: host.bounds.width - 4, y: row * 2.5), window, host)
        XCTAssertEqual(log.toggles, 2)
    }

    func testClickOnTheResetsValueOpensTheTimelineInsteadOfToggling() {
        let log = Log()
        let (window, host) = host(expanded: true, log: log)
        let resetsLine = DashboardMetricLine.height * 4.5
        let shown = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
        click(CGPoint(x: DashboardBox.textInset + DashboardAccountSection<EmptyView>.indent + 60 + DashboardMetricLine.columnSpacing + 8, y: resetsLine), window, host)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertTrue(NSApp.windows.contains { $0.isVisible && !shown.contains(ObjectIdentifier($0)) }, "the resets popover opens")
        XCTAssertEqual(log.toggles, 0)
        click(CGPoint(x: 4, y: resetsLine), window, host)
        XCTAssertEqual(log.toggles, 1)
    }

    func testDragOnTheRowDoesNotToggle() {
        let log = Log()
        let (window, host) = host(expanded: false, log: log)
        let start = CGPoint(x: host.bounds.width / 2, y: host.bounds.height / 2)
        send(.leftMouseDown, at: start, window, host)
        send(.leftMouseDragged, at: CGPoint(x: start.x, y: start.y + 12), window, host)
        send(.leftMouseUp, at: CGPoint(x: start.x, y: start.y + 12), window, host)
        XCTAssertGreaterThan(log.drags, 0)
        XCTAssertEqual(log.toggles, 0)
    }

    private func host(expanded: Bool, log: Log) -> (NSWindow, NSView) {
        let view = DashboardAccountSection(
            account: account,
            plan: "Max 5x",
            isExpanded: expanded,
            onToggleExpanded: { log.toggles += 1 },
            handle: { AnyView($0.highPriorityGesture(DragGesture(minimumDistance: 4).onChanged { _ in log.drags += 1 })) }
        ) { DashboardMetricLine(data: $0.data, labelWidth: 60) }
        .frame(width: 300)
        .environment(\.hoverTooltipsDisabled, true)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        // Off every screen: the window must be ordered in to take events, never seen.
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        addTeardownBlock { window.close() }
        return (window, host)
    }

    private func click(_ point: CGPoint, _ window: NSWindow, _ host: NSView) {
        send(.leftMouseDown, at: point, window, host)
        send(.leftMouseUp, at: point, window, host)
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
            clickCount: 1,
            pressure: type == .leftMouseUp ? 0 : 1
        )!
        window.sendEvent(event)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}

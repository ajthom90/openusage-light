import AppKit
import SwiftUI
import XCTest
@testable import OpenUsage

/// An account isn't a click target. Its name line drags it, each metric line drags itself, and the Resets
/// value is the one thing that acts on a click: it opens the resets timeline.
@MainActor
final class DashboardAccountSectionTests: XCTestCase {
    private final class Log {
        var accountDrags = 0
        var metricDrags = 0
    }

    private static let labelWidth: CGFloat = 60

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

    func testClickOnTheResetsValueOpensItsPopover() {
        let log = Log()
        let (window, host) = host(log: log)
        let resetsLine = DashboardMetricLine.height * 4.5
        let shown = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
        func popoverIsOpen() -> Bool { NSApp.windows.contains { $0.isVisible && !shown.contains(ObjectIdentifier($0)) } }

        click(CGPoint(x: DashboardBox.textInset + 4, y: resetsLine), window, host)
        XCTAssertFalse(popoverIsOpen(), "a click on the label opens nothing")

        click(CGPoint(x: DashboardBox.textInset + Self.labelWidth + DashboardMetricLine.columnSpacing + 8, y: resetsLine), window, host)
        XCTAssertTrue(popoverIsOpen(), "a click on the value opens the resets popover")
        XCTAssertEqual(log.accountDrags + log.metricDrags, 0)
    }

    func testTheNameLineDragsTheAccountAndAMetricLineDragsItself() {
        let log = Log()
        let (window, host) = host(log: log)
        let row = DashboardMetricLine.height
        // The empty end of the name line belongs to it too.
        drag(from: CGPoint(x: host.bounds.width - 20, y: row / 2), window, host)
        XCTAssertGreaterThan(log.accountDrags, 0)
        XCTAssertEqual(log.metricDrags, 0)

        log.accountDrags = 0
        drag(from: CGPoint(x: host.bounds.width / 2, y: row * 1.5), window, host)
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
            DashboardMetricLine(data: line.data, labelWidth: Self.labelWidth)
                .contentShape(Rectangle())
                .highPriorityGesture(DragGesture(minimumDistance: 4).onChanged { _ in log.metricDrags += 1 })
        }
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
            clickCount: 1,
            pressure: type == .leftMouseUp ? 0 : 1
        )!
        window.sendEvent(event)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}

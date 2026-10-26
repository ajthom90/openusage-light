import Foundation

/// The resets popover's model: one node per instant at which something in the account resets or runs
/// out, soonest first. Windows that reset together share a node ("Weekly, Fable reset"); a window
/// projected to run out before its reset adds a red "runs out" node with how long before the reset it
/// hits. Pure and static, so the phrasing and ordering are unit-testable without a view.
enum AccountResetsTimeline {
    struct Node: Identifiable, Equatable {
        let id: String
        let date: Date
        /// "Session resets", "Weekly, Fable reset", "Weekly runs out".
        let title: String
        /// "Today 5:50 PM · in 3h 50m".
        let when: String
        /// "3 days before it resets", on a run-out node.
        let runway: String?
        /// `.critical` on a run-out node; `.normal` on a reset.
        let severity: WidgetData.MeterSeverity
        /// Whether the node is about the metric under the pointer.
        let emphasized: Bool
    }

    /// The account's nodes, from its lines, with the hovered line's nodes emphasized.
    static func nodes(for lines: [DashboardLine], hovered lineID: String?, now: Date = Date()) -> [Node] {
        struct Reset {
            let key: Int
            let date: Date
            var labels: [String]
            var emphasized: Bool
        }
        var resets: [Reset] = []
        var runOuts: [Node] = []
        for line in lines {
            let data = line.data
            guard data.hasData, data.isBounded, let resetsAt = data.resetsAt, !data.isFreshSessionWindow(now: now) else {
                continue
            }
            let key = Int((resetsAt.timeIntervalSinceReferenceDate / 60).rounded())
            let emphasized = line.id == lineID
            if let index = resets.firstIndex(where: { $0.key == key }) {
                resets[index].labels.append(data.title)
                resets[index].emphasized = resets[index].emphasized || emphasized
            } else {
                resets.append(Reset(key: key, date: resetsAt, labels: [data.title], emphasized: emphasized))
            }
            if let runsOut = data.runsOutAt(now: now) {
                runOuts.append(Node(
                    id: "runout:" + line.id, date: runsOut, title: data.title + " runs out",
                    when: when(runsOut, now: now), runway: runway(from: runsOut, to: resetsAt),
                    severity: .critical, emphasized: emphasized
                ))
            }
        }
        let resetNodes = resets.map { reset in
            Node(
                id: "reset:\(reset.key)", date: reset.date,
                title: reset.labels.joined(separator: ", ") + (reset.labels.count > 1 ? " reset" : " resets"),
                when: when(reset.date, now: now), runway: nil, severity: .normal, emphasized: reset.emphasized
            )
        }
        return (resetNodes + runOuts).sorted { $0.date < $1.date }
    }

    /// "Today 5:50 PM · in 3h 50m".
    static func when(_ date: Date, now: Date) -> String {
        let relative = date.timeIntervalSince(now) <= 5 * 60
            ? Formatters.imminent
            : "in " + (Formatters.compactDuration(date.timeIntervalSince(now)) ?? Formatters.imminent)
        return Formatters.dayClock(date, now: now) + " · " + relative
    }

    /// How long before the reset the quota runs out: "3 days before it resets", "a day", "6 hours", or
    /// "just before it resets". `nil` when the run-out is not before the reset.
    static func runway(from runsOut: Date, to resetsAt: Date) -> String? {
        let hours = resetsAt.timeIntervalSince(runsOut) / 3600
        guard hours > 0 else { return nil }
        if hours < 1 { return "Just before it resets" }
        if hours < 18 {
            let n = Int(hours.rounded())
            return "\(n) \(n == 1 ? "hour" : "hours") before it resets"
        }
        if hours < 36 { return "A day before it resets" }
        return "\(Int((hours / 24).rounded())) days before it resets"
    }
}

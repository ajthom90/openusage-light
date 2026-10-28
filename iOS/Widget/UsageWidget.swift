import OpenUsageMobile
import OpenUsageSync
import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}

/// WidgetKit's completion handlers are not `Sendable`; they are called once, from the task that owns them.
private struct Completion<Value>: @unchecked Sendable {
    let call: (Value) -> Void
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        let done = Completion(call: completion)
        Task { done.call(await entry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let done = Completion(call: completion)
        Task {
            let entry = await entry()
            // iOS decides when to actually reload; ask for about every fifteen minutes.
            done.call(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }

    /// Fresh from iCloud when reachable, else the last document the app saved, else example numbers.
    private func entry() async -> UsageEntry {
        if let container = Bundle.main.object(forInfoDictionaryKey: "ICloudContainer") as? String, !container.isEmpty,
           let published = try? await CloudLimitsStore(containerIdentifier: container).fetch() {
            SharedLimits.saveMacDisplay(published.displayMode)
            if let snapshot = UsageSnapshot(document: published.document) {
                SharedLimits.save(published.document)
                return UsageEntry(date: Date(), snapshot: snapshot)
            }
        }
        if let document = SharedLimits.load(), let snapshot = UsageSnapshot(document: document) {
            return UsageEntry(date: Date(), snapshot: snapshot)
        }
        return UsageEntry(date: Date(), snapshot: .sample())
    }
}

struct UsageWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        UsageWidgetView(snapshot: entry.snapshot, family: mapped)
    }

    private var mapped: UsageWidgetFamily {
        switch family {
        case .systemSmall: .small
        case .systemMedium: .medium
        case .accessoryCircular: .lockCircular
        case .accessoryRectangular: .lockRectangular
        default: .large
        }
    }
}

struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenUsageUsage", provider: UsageProvider()) { entry in
            UsageWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Usage")
        .description("How much of each limit you have used, from your Mac.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct OpenUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageWidget()
    }
}

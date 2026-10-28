import Foundation
import OpenUsageSync

/// What the app does when CloudKit says the Mac published: fetch the document and keep it where the app and
/// its widget can read it.
public enum BackgroundSync {
    /// Subscribes this device to the Mac's publishes. Failures are ignored: the app still refreshes when opened.
    public static func subscribe(containerIdentifier: String?) async {
        guard let container = containerIdentifier, !container.isEmpty else { return }
        do {
            try await CloudLimitsStore(containerIdentifier: container).subscribeToChanges()
            note("subscribed \(Date())")
        } catch {
            note("subscribe failed: \(error.localizedDescription)")
        }
    }

    /// A line about the last subscription or push, kept beside the saved document so a problem with push
    /// delivery can be read back from a device that cannot show a console.
    public static func note(_ text: String, topic: String = "subscription") {
        SharedLimits.defaults.set(text, forKey: "openusage.sync.note.\(topic)")
    }

    /// Fetches and saves the latest document. `true` when there was something new to show.
    public static func refresh(containerIdentifier: String?) async -> Bool {
        note("push received \(Date())", topic: "push")
        guard let container = containerIdentifier, !container.isEmpty,
              let published = try? await CloudLimitsStore(containerIdentifier: container).fetch(),
              UsageSnapshot(document: published.document) != nil else { return false }
        SharedLimits.saveMacDisplay(published.displayMode)
        SharedLimits.save(published.document)
        return true
    }
}

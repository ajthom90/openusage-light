import Foundation
import Observation
import OpenUsageCore
import OpenUsageSync

/// What the phone app shows, and where it came from.
@MainActor
@Observable
public final class MobileModel {
    public enum Source: Equatable, Sendable {
        /// Fetched from iCloud just now.
        case cloud
        /// The last document received, shown because a fetch failed or has not finished.
        case saved
        /// Built-in example numbers, shown when no iCloud container is configured or nothing was ever published.
        case sample
    }

    public private(set) var accounts: [MobileAccount] = []
    public private(set) var generatedAt: Date?
    public private(set) var source: Source = .sample
    public private(set) var message: String?
    public private(set) var isLoading = false
    /// Whether the user follows the Mac's "Show Usage As" setting or has chosen a reading on this device.
    public private(set) var choice: DisplayChoice

    private let store: CloudLimitsStore?
    private let defaults: UserDefaults
    private var document: Data?

    /// `containerIdentifier` is empty or `nil` when iCloud is not set up, which leaves the example numbers.
    public init(containerIdentifier: String?, defaults: UserDefaults = SharedLimits.defaults) {
        store = containerIdentifier.flatMap { $0.isEmpty ? nil : CloudLimitsStore(containerIdentifier: $0) }
        self.defaults = defaults
        choice = SharedLimits.loadChoice(from: defaults)
        if let saved = SharedLimits.load(from: defaults), apply(saved) { source = .saved } else { applySample() }
    }

    public func setChoice(_ new: DisplayChoice) {
        choice = new
        SharedLimits.saveChoice(new, to: defaults)
        if let document { _ = apply(document) } else { applySample() }
    }

    public func refresh() async {
        guard let store else {
            message = "iCloud is not set up in this build, so these are example numbers."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            guard let published = try await store.fetch() else {
                message = "Nothing has been published yet. Turn on iCloud sync in OpenUsage Light on your Mac."
                return
            }
            SharedLimits.saveMacDisplay(published.displayMode, to: defaults)
            if apply(published.document) {
                SharedLimits.save(published.document, to: defaults)
                source = .cloud
                message = nil
            } else {
                message = "The Mac published data this version can't read. Update this app."
            }
        } catch {
            message = "Couldn't reach iCloud: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func apply(_ data: Data) -> Bool {
        guard let snapshot = UsageSnapshot(document: data, display: SharedLimits.resolvedDisplay(from: defaults)) else { return false }
        document = data
        accounts = snapshot.accounts
        generatedAt = snapshot.generatedAt
        return true
    }

    private func applySample() {
        source = .sample
        let snapshot = UsageSnapshot.sample(display: SharedLimits.resolvedDisplay(from: defaults))
        accounts = snapshot.accounts
        generatedAt = snapshot.generatedAt
    }
}

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

    private let store: CloudLimitsStore?
    private let defaults: UserDefaults

    /// `containerIdentifier` is empty or `nil` when iCloud is not set up, which leaves the example numbers.
    public init(containerIdentifier: String?, defaults: UserDefaults = SharedLimits.defaults) {
        store = containerIdentifier.flatMap { $0.isEmpty ? nil : CloudLimitsStore(containerIdentifier: $0) }
        self.defaults = defaults
        if let data = SharedLimits.load(from: defaults), apply(data) { source = .saved } else { applySample() }
    }

    public func refresh() async {
        guard let store else {
            message = "iCloud is not set up in this build, so these are example numbers."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            guard let data = try await store.fetch() else {
                message = "Nothing has been published yet. Turn on iCloud sync in OpenUsage Light on your Mac."
                return
            }
            if apply(data) {
                SharedLimits.save(data, to: defaults)
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
        guard let envelope = try? LimitsEnvelope.decode(data) else { return false }
        accounts = MobileAccount.accounts(in: envelope)
        generatedAt = envelope.generatedAt
        return true
    }

    private func applySample() {
        source = .sample
        _ = apply(Data(SampleLimits.json().utf8))
    }
}

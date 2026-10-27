import Foundation

/// Refreshes one account against its provider and the snapshot cache: a stored snapshot younger than the
/// refresh interval is reused, anything else is fetched under a deadline and stored when it succeeds.
/// A failed refresh keeps the last good snapshot and reports the failure, so a surface can keep showing
/// what it had and say why it is out of date. Platform-neutral; the `openusage` command and the Windows
/// dashboard both refresh through it.
@MainActor
package struct SnapshotRefresher {
    package struct Result: Sendable {
        package let snapshot: ProviderSnapshot?
        package let failure: LimitsEnvelope.Failure?
    }

    package let cache: ProviderSnapshotCache
    package var now: () -> Date = Date.init
    package var refreshTimeout: TimeInterval = ProviderRefreshDeadline.defaultTimeout
    package var freshFor: TimeInterval = RefreshSetting.interval

    package init(
        cache: ProviderSnapshotCache,
        now: @escaping () -> Date = Date.init,
        refreshTimeout: TimeInterval = ProviderRefreshDeadline.defaultTimeout,
        freshFor: TimeInterval = RefreshSetting.interval
    ) {
        self.cache = cache
        self.now = now
        self.refreshTimeout = refreshTimeout
        self.freshFor = freshFor
    }

    package func fetch(_ runtime: AccountProviderRuntime, force: Bool) async -> Result {
        let id = runtime.provider.id
        let stored = cache.loadSnapshots(providerIDs: [id])[id]
        // The cache's own freshness gate only trusts snapshots written by this process; a one-shot
        // command never wrote any, so judge the stored snapshot by its age instead.
        if !force, let stored, now().timeIntervalSince(stored.refreshedAt) < freshFor {
            return Result(snapshot: stored, failure: nil)
        }
        guard let refreshed = await ProviderRefreshDeadline.snapshot(from: runtime, force: force, timeout: refreshTimeout) else {
            return failed(id, keeping: stored, "Refresh timed out after \(Int(refreshTimeout))s")
        }
        if let message = refreshed.lines.lazy.compactMap(Self.errorText).first {
            return failed(id, keeping: stored, message)
        }
        cache.store(refreshed)
        return Result(snapshot: refreshed, failure: nil)
    }

    private func failed(_ id: String, keeping stored: ProviderSnapshot?, _ message: String) -> Result {
        Result(snapshot: stored, failure: LimitsEnvelope.Failure(providerId: id, message: message))
    }

    /// The friendly message of an error snapshot (the provider's badge text, which never carries a
    /// credential or a response body).
    private static func errorText(_ line: MetricLine) -> String? {
        guard line.isError, case .badge(_, let text, _, _) = line else { return nil }
        return text
    }
}

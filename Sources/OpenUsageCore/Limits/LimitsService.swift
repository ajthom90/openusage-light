import Foundation

/// The refresh-and-report engine behind the `openusage` command: the app's own account store, provider
/// runtimes, and snapshot cache, run once and read out as a `LimitsEnvelope`.
///
/// A normal read reuses a stored snapshot younger than the refresh interval and refreshes the rest;
/// `force` bypasses that, exactly like the dashboard's manual refresh. A refresh that fails keeps the
/// last good snapshot in the output and reports the failure in `errors`.
@MainActor
package struct LimitsService {
    package struct Outcome {
        package let envelope: LimitsEnvelope
        /// `true` when at least one account's refresh failed.
        package var hadFailures: Bool { !envelope.errors.isEmpty }
    }

    package enum Failure: Error, Equatable {
        /// The name matches neither a provider nor an account.
        case unknownProvider(String)
    }

    package let accounts: [Account]
    package let vault: any CredentialVault
    package let cache: ProviderSnapshotCache
    /// The user's saved dashboard order of account cards; accounts it doesn't name follow in the order
    /// they were added.
    package let savedOrder: [String]
    package var http: any HTTPClient = URLSessionHTTPClient()
    package var now: () -> Date = Date.init
    package var refreshTimeout: TimeInterval = ProviderRefreshDeadline.defaultTimeout
    package var freshFor: TimeInterval = RefreshSetting.interval

    /// The accounts a name selects, in dashboard order. A provider id (`claude`) selects every account
    /// of that provider and an account id (`claude@1a2b3c4d`) selects that one; matching is plain
    /// string comparison, so the same name always selects the same accounts.
    package func accounts(matching name: String?) throws -> [Account] {
        let ordered = Self.ordered(accounts, by: savedOrder)
        guard let name else { return ordered }
        let matched = ordered.filter { $0.kind.rawValue == name || $0.cardID == name }
        guard !matched.isEmpty else { throw Failure.unknownProvider(name) }
        return matched
    }

    package func run(provider name: String?, force: Bool) async throws -> Outcome {
        let selected = try accounts(matching: name)
        let runtimes = selected.map { AccountProviderRuntime(account: $0, vault: vault, http: http, now: now) }
        // Every account refreshes at once; they all run on the main actor and interleave at their awaits.
        let refresher = SnapshotRefresher(cache: cache, now: now, refreshTimeout: refreshTimeout, freshFor: freshFor)
        let tasks = runtimes.map { runtime in
            Task { @MainActor in await refresher.fetch(runtime, force: force) }
        }
        var entries: [LimitsProjection.Entry] = []
        var failures: [LimitsEnvelope.Failure] = []
        for (runtime, task) in zip(runtimes, tasks) {
            let fetched = await task.value
            entries.append(LimitsProjection.Entry(
                account: runtime.account, snapshot: fetched.snapshot, descriptors: runtime.widgetDescriptors
            ))
            if let failure = fetched.failure { failures.append(failure) }
        }
        let envelope = LimitsProjection.envelope(
            entries: entries,
            failures: failures,
            order: selected.map(\.cardID),
            now: now(),
            freshFor: freshFor
        )
        return Outcome(envelope: envelope)
    }

    private static func ordered(_ accounts: [Account], by saved: [String]) -> [Account] {
        let position = Dictionary(saved.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let known = accounts.filter { position[$0.cardID] != nil }.sorted { position[$0.cardID]! < position[$1.cardID]! }
        return known + accounts.filter { position[$0.cardID] == nil }
    }
}

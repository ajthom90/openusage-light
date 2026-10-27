import Foundation

/// What a single provider's refresh actually did this pass, so `refreshAll` can summarize the batch
/// from real outcomes rather than cumulative error state. `.backedOff` is a probe deliberately skipped
/// because the provider failed within the last `failureRetryBackoff` — distinct from `.skipped`
/// (unknown / already in flight) so a wake-burst's suppression is visible in the logs.
package enum RefreshOutcome: Sendable { case refreshed, failed, cacheHit, skipped, backedOff }

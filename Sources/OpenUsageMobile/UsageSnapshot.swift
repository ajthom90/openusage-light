import Foundation
import OpenUsageCore

/// What a widget (or any other reader outside this package) needs from a limits document.
public struct UsageSnapshot: Equatable, Sendable {
    public let accounts: [MobileAccount]
    public let generatedAt: Date

    public init?(document: Data) {
        guard let envelope = try? LimitsEnvelope.decode(document) else { return nil }
        accounts = MobileAccount.accounts(in: envelope)
        generatedAt = envelope.generatedAt
    }

    /// Example numbers for the widget gallery and for a build with no iCloud.
    public static func sample(now: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(document: Data(SampleLimits.json(now: now).utf8))!
    }
}

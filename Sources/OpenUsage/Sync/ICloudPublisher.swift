import Foundation
import OpenUsageCore
import OpenUsageSync

/// Publishes the dashboard's limits document to iCloud so the iPhone and iPad apps can show it.
///
/// Off unless this build was signed with an iCloud container (`ICloudContainer` in Info.plist) and the user
/// turned it on in Settings. It publishes the same provider-reported document the `openusage` command
/// prints: no tokens, keys, or other credentials ever leave the Mac.
@MainActor
final class ICloudPublisher {
    static let enabledKey = "iCloudSyncEnabled"
    static let encryptKey = "iCloudSyncEncrypted"

    /// The container this build was signed for, or `nil` for a build without iCloud.
    static var containerIdentifier: String? {
        (Bundle.main.object(forInfoDictionaryKey: "ICloudContainer") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private let store: CloudLimitsStore?
    private let defaults: UserDefaults

    init(containerIdentifier: String? = ICloudPublisher.containerIdentifier, defaults: UserDefaults = .standard) {
        store = containerIdentifier.map { CloudLimitsStore(containerIdentifier: $0) }
        self.defaults = defaults
    }

    /// On by default in a build signed for iCloud; the Settings switch turns it off.
    var isEnabled: Bool { store != nil && (defaults.object(forKey: Self.enabledKey) as? Bool ?? true) }

    /// Whether to publish as an end-to-end encrypted field. Off by default: the Simulator cannot read one.
    var isEncrypting: Bool { defaults.bool(forKey: Self.encryptKey) }

    /// The document for the given accounts, in the user's saved dashboard order.
    static func document(
        entries: [LimitsProjection.Entry], failures: [LimitsEnvelope.Failure] = [], savedOrder: [String], now: Date
    ) throws -> Data {
        let ordered = LimitsService.ordered(entries.map(\.account), by: savedOrder).map(\.cardID)
        var envelope = LimitsProjection.envelope(
            entries: entries, failures: failures, order: ordered, now: now, freshFor: RefreshSetting.interval
        )
        // An account named by its email shows as its provider alone, as Share Screenshot does: the email
        // itself never leaves the Mac.
        for (id, provider) in envelope.providers where provider.account.contains("@") {
            envelope.providers[id]?.account = ""
        }
        return Data(try envelope.json(pretty: false).utf8)
    }

    func publish(
        entries: [LimitsProjection.Entry], failures: [LimitsEnvelope.Failure], savedOrder: [String],
        displayMode: WidgetDisplayMode, now: Date = Date()
    ) async {
        guard isEnabled, let store else { return }
        do {
            let document = try Self.document(entries: entries, failures: failures, savedOrder: savedOrder, now: now)
            try await store.publish(document, generatedAt: now, displayMode: displayMode.rawValue, encrypted: isEncrypting)
            AppLog.info(.refresh, "published \(entries.count) accounts to iCloud")
        } catch {
            // The error text can name the container but never carries the document or any credential.
            AppLog.warn(.refresh, "iCloud publish failed: \(error.localizedDescription)")
        }
    }
}

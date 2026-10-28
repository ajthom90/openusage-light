import CloudKit
import Foundation

/// The one place the Mac publishes its limits document and the iPhone and iPad read it: a single record in
/// the signed-in iCloud user's private CloudKit database, readable only by that iCloud account's devices and
/// encrypted by CloudKit in transit and at rest. It carries provider-reported numbers only, never a token
/// or key, and exactly one device (the Mac) writes it.
///
/// It is a regular field, not a CloudKit end-to-end `encryptedValues` field: those need Apple's Manatee
/// service, which the Simulator's iCloud account does not have, so the phone app could not be developed or
/// tested against them. Moving to an encrypted field is a follow-up to try on real devices.
public struct CloudLimitsStore: Sendable {
    public static let recordType = "Limits"
    public static let recordName = "limits-v1"
    static let documentKey = "limits"
    static let generatedAtKey = "generatedAt"
    static let displayModeKey = "displayMode"

    /// What the Mac published: the limits document, and how its user chose to read usage ("used" or
    /// "remaining"), which the phone follows unless the user overrides it there.
    public struct Published: Sendable {
        public let document: Data
        public let displayMode: String?
    }

    public let containerIdentifier: String

    public init(containerIdentifier: String) {
        self.containerIdentifier = containerIdentifier
    }

    private var database: CKDatabase { CKContainer(identifier: containerIdentifier).privateCloudDatabase }

    /// Replaces the stored document.
    public func publish(_ document: Data, generatedAt: Date, displayMode: String? = nil) async throws {
        let id = CKRecord.ID(recordName: Self.recordName)
        let record: CKRecord
        do {
            record = try await database.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: Self.recordType, recordID: id)
        }
        record[Self.documentKey] = document as CKRecordValue
        record[Self.generatedAtKey] = generatedAt as CKRecordValue
        record[Self.displayModeKey] = displayMode.map { $0 as CKRecordValue }
        _ = try await database.save(record)
    }

    /// What the Mac last published, or `nil` when it has not published anything yet.
    public func fetch() async throws -> Published? {
        do {
            let record = try await database.record(for: CKRecord.ID(recordName: Self.recordName))
            guard let document = record[Self.documentKey] as? Data else { return nil }
            return Published(document: document, displayMode: record[Self.displayModeKey] as? String)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    static let subscriptionID = "limits-v1-changes"

    /// Asks CloudKit to send this device a silent push whenever the Mac publishes, so the app and its
    /// widget can refresh without waiting for a timer. Safe to call on every launch.
    public func subscribeToChanges() async throws {
        do {
            _ = try await database.subscription(for: Self.subscriptionID)
            return
        } catch let error as CKError where error.code == .unknownItem {
            // Not subscribed yet: fall through and create it.
        }
        let subscription = CKQuerySubscription(
            recordType: Self.recordType, predicate: NSPredicate(value: true), subscriptionID: Self.subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try await database.save(subscription)
    }
}

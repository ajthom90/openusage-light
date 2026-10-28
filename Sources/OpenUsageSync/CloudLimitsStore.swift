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

    public let containerIdentifier: String

    public init(containerIdentifier: String) {
        self.containerIdentifier = containerIdentifier
    }

    private var database: CKDatabase { CKContainer(identifier: containerIdentifier).privateCloudDatabase }

    /// Replaces the stored document.
    public func publish(_ document: Data, generatedAt: Date) async throws {
        let id = CKRecord.ID(recordName: Self.recordName)
        let record: CKRecord
        do {
            record = try await database.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: Self.recordType, recordID: id)
        }
        record[Self.documentKey] = document as CKRecordValue
        record[Self.generatedAtKey] = generatedAt as CKRecordValue
        _ = try await database.save(record)
    }

    /// The stored document, or `nil` when the Mac has not published one yet.
    public func fetch() async throws -> Data? {
        do {
            let record = try await database.record(for: CKRecord.ID(recordName: Self.recordName))
            return record[Self.documentKey] as? Data
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }
}

import CloudKit
import Foundation

/// The one place the Mac publishes its limits document and the iPhone and iPad read it: a single record in
/// the signed-in iCloud user's private CloudKit database. The document is stored as an encrypted field, so
/// only devices on that iCloud account can read it. It carries provider-reported numbers only, never a
/// token or key, and exactly one device (the Mac) writes it.
public struct CloudLimitsStore: Sendable {
    public static let recordType = "Limits"
    public static let recordName = "current"
    static let documentKey = "document"
    static let generatedAtKey = "generatedAt"

    public let containerIdentifier: String

    public init(containerIdentifier: String) {
        self.containerIdentifier = containerIdentifier
    }

    private var database: CKDatabase { CKContainer(identifier: containerIdentifier).privateCloudDatabase }

    /// Replaces the stored document. `generatedAt` is kept readable (not encrypted) so a device can see how
    /// old the data is without decrypting it.
    public func publish(_ document: Data, generatedAt: Date) async throws {
        let id = CKRecord.ID(recordName: Self.recordName)
        let record: CKRecord
        do {
            record = try await database.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: Self.recordType, recordID: id)
        }
        record.encryptedValues[Self.documentKey] = document
        record[Self.generatedAtKey] = generatedAt as CKRecordValue
        _ = try await database.save(record)
    }

    /// The stored document, or `nil` when the Mac has not published one yet.
    public func fetch() async throws -> Data? {
        do {
            let record = try await database.record(for: CKRecord.ID(recordName: Self.recordName))
            return record.encryptedValues[Self.documentKey] as? Data
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }
}

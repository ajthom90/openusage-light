import Foundation

package protocol CredentialVault: Sendable {
    func load(_ id: UUID) throws -> AccountCredential?
    func save(_ credential: AccountCredential, for id: UUID) throws
    func delete(_ id: UUID) throws
}

package final class InMemoryCredentialVault: CredentialVault, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: [UUID: AccountCredential] = [:]

    package init() {}

    package func load(_ id: UUID) throws -> AccountCredential? {
        lock.lock()
        defer { lock.unlock() }
        return credentials[id]
    }

    package func save(_ credential: AccountCredential, for id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        credentials[id] = credential
    }

    package func delete(_ id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        credentials.removeValue(forKey: id)
    }
}

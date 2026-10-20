import Foundation
import Security

protocol CredentialVault: Sendable {
    func load(_ id: UUID) throws -> AccountCredential?
    func save(_ credential: AccountCredential, for id: UUID) throws
    func delete(_ id: UUID) throws
}

final class KeychainCredentialVault: CredentialVault, @unchecked Sendable {
    static let service = "com.robinebers.openusage-light.accounts"

    func load(_ id: UUID) throws -> AccountCredential? {
        var query = baseQuery(for: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainVaultError.status(status)
        }
        return try JSONDecoder().decode(AccountCredential.self, from: data)
    }

    func save(_ credential: AccountCredential, for id: UUID) throws {
        let data = try JSONEncoder().encode(credential)
        let query = baseQuery(for: id)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainVaultError.status(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainVaultError.status(status)
        }
    }

    func delete(_ id: UUID) throws {
        let status = SecItemDelete(baseQuery(for: id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainVaultError.status(status)
        }
    }

    private func baseQuery(for id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: id.uuidString
        ]
    }
}

final class InMemoryCredentialVault: CredentialVault, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: [UUID: AccountCredential] = [:]

    func load(_ id: UUID) throws -> AccountCredential? {
        lock.lock()
        defer { lock.unlock() }
        return credentials[id]
    }

    func save(_ credential: AccountCredential, for id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        credentials[id] = credential
    }

    func delete(_ id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        credentials.removeValue(forKey: id)
    }
}

enum KeychainVaultError: Error {
    case status(OSStatus)
}

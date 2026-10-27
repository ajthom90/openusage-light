import Foundation
import OpenUsageCore
import Security

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

enum KeychainVaultError: Error {
    case status(OSStatus)
}

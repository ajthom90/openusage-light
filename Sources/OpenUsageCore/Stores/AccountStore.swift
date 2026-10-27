import Foundation
import Observation

@MainActor
@Observable
package final class AccountStore {
    package static let storageKey = "accounts.v1"

    package private(set) var accounts: [Account]
    package private(set) var lastError: String?
    private let defaults: any SettingsStore
    package let credentialVault: any CredentialVault

    /// A sign-in names an API-key account after its provider, and a provider's name can change: an
    /// account still carrying the old default takes the new one, so its header never reads
    /// "OpenCode — OpenCode Go".
    private static let retiredDefaultLabels: [ProviderKind: String] = [.opencodeGo: "OpenCode Go"]

    package init(defaults: any SettingsStore, vault: any CredentialVault) {
        self.defaults = defaults
        credentialVault = vault
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([Account].self, from: data) else {
            accounts = []
            return
        }
        accounts = decoded.sorted { $0.addedAt < $1.addedAt }
        let stale = accounts.indices.filter { accounts[$0].label == Self.retiredDefaultLabels[accounts[$0].kind] }
        guard !stale.isEmpty else { return }
        for index in stale { accounts[index].label = accounts[index].kind.displayName }
        _ = persist()
    }

    @discardableResult
    package func add(kind: ProviderKind, label: String, credential: AccountCredential) -> Account {
        let account = Account(kind: kind, label: label)
        do {
            try credentialVault.save(credential, for: account.id)
            accounts.append(account)
            if !persist() {
                accounts.removeAll { $0.id == account.id }
                do {
                    try credentialVault.delete(account.id)
                } catch {
                    AppLog.error(LogTag.auth("accounts"), "could not roll back account credential: \(error.localizedDescription)")
                }
            }
        } catch {
            lastError = error.localizedDescription
            AppLog.error(LogTag.auth("accounts"), "could not save account: \(error.localizedDescription)")
        }
        return account
    }

    package func rename(_ id: UUID, to label: String) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        let previous = accounts[index].label
        accounts[index].label = label
        guard !persist() else { return }
        accounts[index].label = previous
    }

    package func remove(_ id: UUID) {
        guard let accountIndex = accounts.firstIndex(where: { $0.id == id }) else { return }
        do {
            let credential = try credentialVault.load(id)
            try credentialVault.delete(id)
            let account = accounts.remove(at: accountIndex)
            guard !persist() else { return }
            accounts.insert(account, at: accountIndex)
            if let credential {
                do {
                    try credentialVault.save(credential, for: id)
                } catch {
                    AppLog.error(LogTag.auth("accounts"), "could not restore account credential: \(error.localizedDescription)")
                }
            }
        } catch {
            lastError = error.localizedDescription
            AppLog.error(LogTag.auth("accounts"), "could not remove account credential: \(error.localizedDescription)")
        }
    }

    package func credential(for id: UUID) throws -> AccountCredential? {
        try credentialVault.load(id)
    }

    /// The account behind a dashboard card, by its `Account.cardID` (the card's `Provider.id`).
    package func account(cardID: String) -> Account? {
        accounts.first { $0.cardID == cardID }
    }

    private func persist() -> Bool {
        do {
            defaults.set(try JSONEncoder().encode(accounts), forKey: Self.storageKey)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            AppLog.error(LogTag.auth("accounts"), "could not persist account list: \(error.localizedDescription)")
            return false
        }
    }
}

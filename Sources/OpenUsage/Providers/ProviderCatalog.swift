import Foundation

@MainActor
enum ProviderCatalog {
    /// One runtime per account in provider order. Runtimes in `existing` are reused for accounts that
    /// are still present, so an account change never resets the others.
    static func make(
        accounts: [Account],
        vault: any CredentialVault,
        reusing existing: [AccountProviderRuntime] = []
    ) -> [AccountProviderRuntime] {
        let providerOrder = Dictionary(uniqueKeysWithValues: ProviderKind.allCases.enumerated().map { ($1, $0) })
        let existingByID = Dictionary(existing.map { ($0.account.id, $0) }, uniquingKeysWith: { first, _ in first })
        return accounts
            .sorted {
                let left = providerOrder[$0.kind, default: Int.max]
                let right = providerOrder[$1.kind, default: Int.max]
                return left == right ? $0.addedAt < $1.addedAt : left < right
            }
            .map { account in
                guard let runtime = existingByID[account.id] else {
                    return AccountProviderRuntime(account: account, vault: vault)
                }
                runtime.update(account)
                return runtime
            }
    }
}

import Foundation

@MainActor
enum ProviderCatalog {
    static func make(accounts: [Account], vault: any CredentialVault) -> [ProviderRuntime] {
        let providerOrder = Dictionary(uniqueKeysWithValues: ProviderKind.allCases.enumerated().map { ($1, $0) })
        return accounts
            .sorted {
                let left = providerOrder[$0.kind, default: Int.max]
                let right = providerOrder[$1.kind, default: Int.max]
                return left == right ? $0.addedAt < $1.addedAt : left < right
            }
            .map { AccountProviderRuntime(account: $0, vault: vault) }
    }
}

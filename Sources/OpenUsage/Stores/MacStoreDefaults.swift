import Foundation
import OpenUsageCore

extension AccountStore {
    /// The app's own account list (in `UserDefaults`) and credentials (in its Keychain service).
    convenience init() {
        self.init(defaults: UserDefaults.standard, vault: KeychainCredentialVault())
    }
}

extension ProviderSnapshotCache {
    /// The app's snapshot cache in `UserDefaults`.
    init() {
        self.init(userDefaults: UserDefaults.standard)
    }
}

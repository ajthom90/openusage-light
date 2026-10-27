import Foundation

/// Where the app keeps its small saved state (the account list, the snapshot cache, the dashboard
/// order): a keyed store of encoded values. The Mac app backs it with `UserDefaults`; other platforms
/// use `FileSettingsStore`.
package protocol SettingsStore: AnyObject, Sendable {
    func data(forKey key: String) -> Data?
    /// Stores `value` (a `Data`) under `key`; `nil` removes it. The signature matches `UserDefaults`.
    func set(_ value: Any?, forKey key: String)
}

#if canImport(Darwin)
/// `UserDefaults` already has exactly these two methods, so the Mac app can pass it wherever a store is
/// wanted. (Other platforms' Foundation doesn't make it `Sendable`; they use `FileSettingsStore`.)
extension UserDefaults: SettingsStore {}
#endif

/// A `SettingsStore` that keeps each value in its own file under a directory, written atomically so a
/// reader in another process (the `openusage` command beside the app) never sees half a value.
package final class FileSettingsStore: SettingsStore, @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()

    package init(directory: URL) {
        self.directory = directory
    }

    package func data(forKey key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return try? Data(contentsOf: url(for: key))
    }

    package func set(_ value: Any?, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        let file = url(for: key)
        guard let data = value as? Data else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            AppLog.warn(.config, "could not save \(key): \(error.localizedDescription)")
        }
    }

    /// One file per key; characters a file name can't hold are percent-encoded.
    private func url(for key: String) -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let name = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
        return directory.appendingPathComponent(name + ".json")
    }
}

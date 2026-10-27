#if os(Windows)
import Foundation
import OpenUsageCore
import WinSDK

/// Stores each account's credential as a file under the app's data directory, encrypted with the
/// Windows data-protection API so only the signed-in Windows user can read it. (Credential Manager would
/// hold a secret too, but caps it near 2.5 KB, which an OAuth token set can exceed.)
package final class DPAPICredentialVault: CredentialVault, @unchecked Sendable {
    package enum VaultError: Error, LocalizedError {
        case windows(operation: String, code: UInt32)

        package var errorDescription: String? {
            switch self {
            case .windows(let operation, let code): "Windows could not \(operation) the saved sign-in (error \(code))."
            }
        }
    }

    private let directory: URL
    private let lock = NSLock()

    package init(directory: URL) {
        self.directory = directory
    }

    package func load(_ id: Foundation.UUID) throws -> AccountCredential? {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: file(id).path) else { return nil }
        let protected = try Data(contentsOf: file(id))
        return try JSONDecoder().decode(AccountCredential.self, from: Self.unprotect(protected))
    }

    package func save(_ credential: AccountCredential, for id: Foundation.UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        let protected = try Self.protect(try JSONEncoder().encode(credential))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try protected.write(to: file(id), options: .atomic)
    }

    package func delete(_ id: Foundation.UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: file(id).path) else { return }
        try FileManager.default.removeItem(at: file(id))
    }

    private func file(_ id: Foundation.UUID) -> URL {
        directory.appendingPathComponent(id.uuidString.lowercased() + ".credential")
    }

    // MARK: - DPAPI

    package static func protect(_ data: Data) throws -> Data {
        try transform(data, operation: "protect") { input, output in
            CryptProtectData(input, nil, nil, nil, nil, DWORD(CRYPTPROTECT_UI_FORBIDDEN), output)
        }
    }

    package static func unprotect(_ data: Data) throws -> Data {
        try transform(data, operation: "read") { input, output in
            CryptUnprotectData(input, nil, nil, nil, nil, DWORD(CRYPTPROTECT_UI_FORBIDDEN), output)
        }
    }

    private static func transform(
        _ data: Data,
        operation: String,
        _ call: (UnsafeMutablePointer<DATA_BLOB>, UnsafeMutablePointer<DATA_BLOB>) -> Bool
    ) throws -> Data {
        var bytes = [UInt8](data)
        var output = DATA_BLOB()
        let succeeded = bytes.withUnsafeMutableBufferPointer { buffer -> Bool in
            var input = DATA_BLOB(cbData: DWORD(buffer.count), pbData: buffer.baseAddress)
            return call(&input, &output)
        }
        guard succeeded else { throw VaultError.windows(operation: operation, code: GetLastError()) }
        defer { LocalFree(output.pbData) }
        return Data(bytes: output.pbData, count: Int(output.cbData))
    }
}
#endif

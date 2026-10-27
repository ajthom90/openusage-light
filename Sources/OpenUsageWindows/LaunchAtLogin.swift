#if os(Windows)
import Foundation
import WinSDK

/// Starting with Windows: a value under the user's `Run` registry key, which needs no administrator rights.
enum LaunchAtLogin {
    private static let keyPath = "Software\\Microsoft\\Windows\\CurrentVersion\\Run"
    private static let valueName = "OpenUsageLight"

    static var isEnabled: Bool {
        var size: DWORD = 0
        return RegGetValueW(
            HKEY_CURRENT_USER, Win32.wide(keyPath), Win32.wide(valueName), DWORD(RRF_RT_REG_SZ), nil, nil, &size
        ) == ERROR_SUCCESS
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        var key: HKEY?
        guard RegCreateKeyExW(
            HKEY_CURRENT_USER, Win32.wide(keyPath), 0, nil, 0, DWORD(KEY_SET_VALUE), nil, &key, nil
        ) == ERROR_SUCCESS, let key else { return false }
        defer { RegCloseKey(key) }
        if enabled {
            guard let path = executablePath() else { return false }
            // Quoted, so a path with spaces still launches.
            let value = Win32.wide("\"\(path)\"")
            return value.withUnsafeBytes { raw in
                RegSetValueExW(key, Win32.wide(valueName), 0, DWORD(REG_SZ), raw.bindMemory(to: BYTE.self).baseAddress, DWORD(raw.count))
            } == ERROR_SUCCESS
        }
        let result = RegDeleteValueW(key, Win32.wide(valueName))
        return result == ERROR_SUCCESS || result == ERROR_FILE_NOT_FOUND
    }

    private static func executablePath() -> String? {
        var buffer = [WCHAR](repeating: 0, count: 1024)
        let length = GetModuleFileNameW(nil, &buffer, DWORD(buffer.count))
        guard length > 0, Int(length) < buffer.count else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF16.self)
    }
}
#endif

#if os(Windows)
import Foundation
import WinSDK

/// Small helpers over the Win32 C API.
enum Win32 {
    /// A null-terminated UTF-16 copy of `string`.
    static func wide(_ string: String) -> [WCHAR] {
        Array(string.utf16) + [0]
    }

    static func color(_ red: Int, _ green: Int, _ blue: Int) -> COLORREF {
        COLORREF(red | (green << 8) | (blue << 16))
    }

    /// Copies `string` into a fixed-size UTF-16 buffer Swift imports as a tuple (a `szTip`-style field).
    static func copy<T>(_ string: String, into field: inout T, capacity: Int) {
        let units = Array(string.utf16.prefix(capacity - 1)) + [0]
        withUnsafeMutableBytes(of: &field) { raw in
            let target = raw.bindMemory(to: WCHAR.self)
            for (index, unit) in units.enumerated() where index < capacity { target[index] = unit }
        }
    }

    /// Scales a 96-dpi measure to `dpi`.
    static func scale(_ value: Int, _ dpi: Int) -> Int32 {
        Int32((Double(value) * Double(dpi) / 96).rounded())
    }

    /// Puts `string` on the clipboard as Unicode text.
    static func copyToClipboard(_ string: String, owner: HWND?) {
        guard OpenClipboard(owner) else { return }
        defer { CloseClipboard() }
        EmptyClipboard()
        let units = wide(string)
        let bytes = units.count * MemoryLayout<WCHAR>.size
        guard let handle = GlobalAlloc(UINT(GMEM_MOVEABLE), SIZE_T(bytes)), let memory = GlobalLock(handle) else { return }
        units.withUnsafeBytes { memory.copyMemory(from: $0.baseAddress!, byteCount: bytes) }
        GlobalUnlock(handle)
        SetClipboardData(UINT(CF_UNICODETEXT), handle)
    }

    /// Whether Windows apps are set to the dark theme.
    static func appsUseDarkTheme() -> Bool {
        var value: DWORD = 1
        var size = DWORD(MemoryLayout<DWORD>.size)
        let status = RegGetValueW(
            HKEY_CURRENT_USER,
            wide("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"),
            wide("AppsUseLightTheme"),
            DWORD(RRF_RT_REG_DWORD),
            nil,
            &value,
            &size
        )
        return status == ERROR_SUCCESS && value == 0
    }
}
#endif

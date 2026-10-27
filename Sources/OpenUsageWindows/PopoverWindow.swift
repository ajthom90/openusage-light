#if os(Windows)
import Foundation
import OpenUsageCore
import WinSDK

/// The tray icon and the popover window it opens. Painting is `PopoverRenderer`'s; this owns the window,
/// the tray icon, scrolling, and clicks.
/// Appends one line to `OpenUsageLight-ui.log` in the user's temp folder, for `--show` runs only: the
/// geometry the window computed, so a screenshot that looks wrong can be explained.
enum UIDebugLog {
    nonisolated(unsafe) static var enabled = false

    static func write(_ line: @autoclosure () -> String) {
        guard enabled else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OpenUsageLight-ui.log")
        let text = line() + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

@MainActor
final class PopoverWindow {
    static var shared: PopoverWindow?

    private static let trayMessage = UINT(WM_APP + 1)
    private static let className = "OpenUsageLightPopover"
    private enum MenuCommand: UInt { case refresh = 1, quit = 2 }

    /// Whether losing focus closes the popover. Off for `--show`, which keeps it up for screenshots.
    var hidesWhenDeactivated = true

    var onRefresh: () -> Void = {}
    var onQuit: () -> Void = {}

    private let model: DashboardModel
    private var window: HWND?
    private var scroll: Int32 = 0
    private var hits: [PopoverRenderer.Hit] = []
    private var hiddenAt: ULONGLONG = 0

    init(model: DashboardModel) {
        self.model = model
    }

    var isVisible: Bool { window.map { IsWindowVisible($0) } ?? false }

    // MARK: - Setup

    func create() -> Bool {
        let instance = GetModuleHandleW(nil)
        var windowClass = WNDCLASSEXW()
        windowClass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        windowClass.lpfnWndProc = popoverWindowProc
        windowClass.hInstance = instance
        windowClass.hCursor = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512))
        let name = Win32.wide(Self.className)
        let registered = name.withUnsafeBufferPointer { buffer -> Bool in
            windowClass.lpszClassName = buffer.baseAddress
            return RegisterClassExW(&windowClass) != 0
        }
        guard registered else { return false }
        window = CreateWindowExW(
            DWORD(WS_EX_TOOLWINDOW | WS_EX_TOPMOST), name, Win32.wide("OpenUsage Light"), DWORD(WS_POPUP),
            0, 0, 10, 10, nil, nil, instance, nil
        )
        guard let window else { return false }
        // Rounded corners on Windows 11 (ignored where unsupported).
        var corner: Int32 = 2
        DwmSetWindowAttribute(window, DWORD(33), &corner, DWORD(MemoryLayout<Int32>.size))
        addTrayIcon()
        return true
    }

    func destroy() {
        guard let window else { return }
        var data = trayData(window)
        Shell_NotifyIconW(DWORD(NIM_DELETE), &data)
        DestroyWindow(window)
        self.window = nil
    }

    private func trayData(_ window: HWND) -> NOTIFYICONDATAW {
        var data = NOTIFYICONDATAW()
        data.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
        data.hWnd = window
        data.uID = 1
        data.uFlags = UINT(NIF_MESSAGE | NIF_ICON | NIF_TIP)
        data.uCallbackMessage = Self.trayMessage
        data.hIcon = LoadIconW(nil, UnsafePointer<WCHAR>(bitPattern: 32512))
        Win32.copy("OpenUsage Light", into: &data.szTip, capacity: 128)
        return data
    }

    private func addTrayIcon() {
        guard let window else { return }
        var data = trayData(window)
        Shell_NotifyIconW(DWORD(NIM_ADD), &data)
    }

    // MARK: - Showing

    func toggle() {
        if isVisible { hide("toggle"); return }
        // A click on the tray icon first deactivates (and so hides) the popover; don't reopen it at once.
        guard GetTickCount64() - hiddenAt > 250 else { return }
        show()
    }

    func show() {
        guard let window else { return }
        scroll = 0
        resize()
        ShowWindow(window, SW_SHOW)
        let foreground = SetForegroundWindow(window)
        var rect = RECT()
        GetWindowRect(window, &rect)
        UIDebugLog.write("show visible=\(isVisible) foreground=\(foreground) rect=\(rect.left),\(rect.top),\(rect.right),\(rect.bottom)")
        invalidate()
    }

    func hide(_ reason: String = "unspecified") {
        guard let window, isVisible else { return }
        UIDebugLog.write("hide reason=\(reason)")
        ShowWindow(window, SW_HIDE)
        hiddenAt = GetTickCount64()
    }

    func invalidate() {
        guard let window, isVisible else { return }
        resize()
        InvalidateRect(window, nil, false)
    }

    private var dpi: Int { Int(GetDpiForSystem()) }

    private func renderer() -> PopoverRenderer {
        PopoverRenderer(sections: model.sections, palette: .current(), dpi: dpi, status: statusText())
    }

    private func statusText() -> String {
        if model.isRefreshing { return "Refreshing…" }
        guard let last = model.lastRefreshed else { return "Not updated yet" }
        let age = Date().timeIntervalSince(last)
        return "Updated " + (age < 60 ? "just now" : (Formatters.compactDuration(age).map { "\($0) ago" } ?? "a while ago"))
    }

    /// Sizes the window to its content, bottom-right of the work area, above the taskbar.
    private func resize() {
        guard let window else { return }
        var work = RECT()
        SystemParametersInfoW(UINT(SPI_GETWORKAREA), 0, &work, 0)
        let renderer = renderer()
        let margin = Win32.scale(12, dpi)
        let width = Win32.scale(PopoverRenderer.width, dpi)
        let maxHeight = (work.bottom - work.top) - margin * 2
        let height = min(renderer.contentHeight() + renderer.footerPixels, maxHeight)
        let maxScroll = max(renderer.contentHeight() + renderer.footerPixels - height, 0)
        scroll = min(max(scroll, 0), maxScroll)
        UIDebugLog.write("resize dpi=\(dpi) work=\(work.left),\(work.top),\(work.right),\(work.bottom) size=\(width)x\(height) content=\(renderer.contentHeight()) footer=\(renderer.footerPixels) sections=\(model.sections.count)")
        SetWindowPos(
            window, UnsafeMutablePointer<HWND__>(bitPattern: -1), work.right - width - margin, work.bottom - height - margin, width, height,
            UINT(SWP_NOACTIVATE)
        )
    }

    // MARK: - Messages

    func handle(_ hwnd: HWND?, _ message: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT {
        switch message {
        case UINT(WM_PAINT):
            paint(hwnd)
            return 0
        case UINT(WM_ERASEBKGND):
            return 1
        case UINT(WM_ACTIVATE):
            if (wParam & 0xFFFF) == UInt(WA_INACTIVE), hidesWhenDeactivated { hide("deactivated") }
            return 0
        case UINT(WM_KEYDOWN):
            if wParam == UInt(VK_ESCAPE) { hide("escape") }
            return 0
        case UINT(WM_MOUSEWHEEL):
            let delta = Int32(Int16(truncatingIfNeeded: wParam >> 16))
            scroll -= delta / 120 * Win32.scale(40, dpi)
            invalidate()
            return 0
        case UINT(WM_LBUTTONUP):
            click(x: Int32(Int16(truncatingIfNeeded: lParam)), y: Int32(Int16(truncatingIfNeeded: lParam >> 16)))
            return 0
        case Self.trayMessage:
            switch UINT(truncatingIfNeeded: lParam & 0xFFFF) {
            case UINT(WM_LBUTTONUP): toggle()
            case UINT(WM_RBUTTONUP): showMenu(hwnd)
            default: break
            }
            return 0
        case UINT(WM_COMMAND):
            switch MenuCommand(rawValue: UInt(wParam & 0xFFFF)) {
            case .refresh: onRefresh()
            case .quit: onQuit()
            case nil: break
            }
            return 0
        default:
            return DefWindowProcW(hwnd, message, wParam, lParam)
        }
    }

    private func click(x: Int32, y: Int32) {
        for hit in hits where x >= hit.rect.left && x <= hit.rect.right && y >= hit.rect.top && y <= hit.rect.bottom {
            switch hit.button {
            case .refresh: onRefresh()
            case .quit: onQuit()
            }
        }
    }

    private func showMenu(_ hwnd: HWND?) {
        guard let menu = CreatePopupMenu() else { return }
        AppendMenuW(menu, UINT(MF_STRING), UINT_PTR(MenuCommand.refresh.rawValue), Win32.wide("Refresh"))
        AppendMenuW(menu, UINT(MF_STRING), UINT_PTR(MenuCommand.quit.rawValue), Win32.wide("Quit OpenUsage Light"))
        var cursor = POINT()
        GetCursorPos(&cursor)
        // Without this the menu stays up after a click elsewhere.
        SetForegroundWindow(hwnd)
        TrackPopupMenu(menu, UINT(TPM_RIGHTBUTTON | TPM_BOTTOMALIGN), cursor.x, cursor.y, 0, hwnd, nil)
        DestroyMenu(menu)
    }

    private func paint(_ hwnd: HWND?) {
        var paint = PAINTSTRUCT()
        guard let hdc = BeginPaint(hwnd, &paint) else { return }
        defer { EndPaint(hwnd, &paint) }
        var client = RECT()
        GetClientRect(hwnd, &client)
        let size = SIZE(cx: client.right, cy: client.bottom)
        UIDebugLog.write("paint client=\(client.right)x\(client.bottom)")
        guard let memory = CreateCompatibleDC(hdc), let bitmap = CreateCompatibleBitmap(hdc, size.cx, size.cy) else { return }
        let previous = SelectObject(memory, bitmap)
        hits = renderer().draw(on: memory, size: size, scroll: scroll)
        BitBlt(hdc, 0, 0, size.cx, size.cy, memory, 0, 0, DWORD(SRCCOPY))
        SelectObject(memory, previous)
        DeleteObject(bitmap)
        DeleteDC(memory)
    }
}

/// A window handle carried into main-actor code. The window procedure always runs on the thread that
/// created the window, which is the main thread, so the handle never crosses threads.
private struct WindowHandle: @unchecked Sendable {
    let value: HWND?
}

private let popoverWindowProc: @convention(c) (HWND?, UINT, WPARAM, LPARAM) -> LRESULT = { hwnd, message, wParam, lParam in
    let handle = WindowHandle(value: hwnd)
    return MainActor.assumeIsolated {
        PopoverWindow.shared?.handle(handle.value, message, wParam, lParam)
            ?? DefWindowProcW(handle.value, message, wParam, lParam)
    }
}
#endif

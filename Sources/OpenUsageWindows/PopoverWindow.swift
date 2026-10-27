#if os(Windows)
import Foundation
import OpenUsageCore
import WinSDK

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

/// What the popover draws, copied out of the dashboard model so the window's own thread can read it.
struct PopoverState: Sendable {
    var sections: [DashboardSection] = []
    var isRefreshing = false
    var lastRefreshed: Date?
}

/// The tray icon and the popover window it opens. Painting is `PopoverRenderer`'s; this owns the window,
/// the tray icon, scrolling, and clicks.
///
/// The window lives on a dedicated thread that does nothing but pump Windows messages (`runMessageLoop`),
/// independent of Swift concurrency's executors, so it can never be starved into "not responding". Other
/// threads change it only through `update(_:)`, which stores a snapshot and posts a message.
final class PopoverWindow: @unchecked Sendable {
    nonisolated(unsafe) static var shared: PopoverWindow?

    private static let trayMessage = UINT(WM_APP + 1)
    private static let stateMessage = UINT(WM_APP + 2)
    private static let className = "OpenUsageLightPopover"
    private enum MenuCommand: UInt { case refresh = 1, quit = 2 }

    /// Whether losing focus closes the popover. Off for `--show`, which keeps it up for screenshots.
    var hidesWhenDeactivated = true

    /// Called on the window's thread.
    var onRefresh: @Sendable () -> Void = {}

    private let state = Locked<PopoverState>(initialState: PopoverState())
    /// The window handle as an integer, so other threads can post to it without sharing a pointer.
    private let windowBits = Locked<UInt>(initialState: 0)
    private var window: HWND?
    private var scroll: Int32 = 0
    private var hits: [PopoverRenderer.Hit] = []
    private var hiddenAt: ULONGLONG = 0

    init() {}

    var isVisible: Bool { window.map { IsWindowVisible($0) } ?? false }

    /// The window's rectangle on screen, in pixels.
    func screenRect() -> RECT? {
        guard let window else { return nil }
        var rect = RECT()
        return GetWindowRect(window, &rect) ? rect : nil
    }

    // MARK: - From other threads

    /// Replaces what the popover shows and asks its thread to redraw. Safe from any thread.
    func update(_ newState: PopoverState) {
        state.withLock { $0 = newState }
        let bits = windowBits.withLock { $0 }
        guard bits != 0, let handle = HWND(bitPattern: bits) else { return }
        PostMessageW(handle, Self.stateMessage, 0, 0)
    }

    // MARK: - The window's thread

    /// Creates the window and tray icon on the calling thread and pumps messages until quit. Returns
    /// `false` if the window could not be created.
    func runMessageLoop(showAtStart: Bool) -> Bool {
        Self.shared = self
        guard create() else { return false }
        if showAtStart { show() }
        var message = MSG()
        while GetMessageW(&message, nil, 0, 0) {
            TranslateMessage(&message)
            DispatchMessageW(&message)
        }
        destroy()
        return true
    }

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
        windowBits.withLock { $0 = UInt(bitPattern: window) }
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
        var cloaked: DWORD = 0
        DwmGetWindowAttribute(window, DWORD(14), &cloaked, DWORD(MemoryLayout<DWORD>.size))
        if UIDebugLog.enabled { SetTimer(window, 1, 3000, nil) }
        UIDebugLog.write("thread=\(GetCurrentThreadId()) show visible=\(isVisible) foreground=\(foreground) cloaked=\(cloaked) iconic=\(IsIconic(window)) rect=\(rect.left),\(rect.top),\(rect.right),\(rect.bottom)")
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
        let snapshot = state.withLock { $0 }
        return PopoverRenderer(sections: snapshot.sections, palette: .current(), dpi: dpi, status: statusText(snapshot))
    }

    private func statusText(_ snapshot: PopoverState) -> String {
        if snapshot.isRefreshing { return "Refreshing…" }
        guard let last = snapshot.lastRefreshed else { return "Not updated yet" }
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
        UIDebugLog.write("resize dpi=\(dpi) work=\(work.left),\(work.top),\(work.right),\(work.bottom) size=\(width)x\(height) content=\(renderer.contentHeight()) footer=\(renderer.footerPixels) sections=\(renderer.sections.count)")
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
        case Self.stateMessage:
            invalidate()
            return 0
        case UINT(WM_TIMER):
            if wParam == 1 { selfGrab(hwnd) }
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
            case .quit: PostQuitMessage(0)
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
            case .quit: PostQuitMessage(0)
            }
        }
    }

    /// For `--show`: three seconds after showing, copy what the screen shows under the window to a file.
    private func selfGrab(_ hwnd: HWND?) {
        KillTimer(hwnd, 1)
        guard let rect = screenRect() else { return }
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("OpenUsageLight-screen.bmp")
        UIDebugLog.write("screen grab \(ScreenGrab.write(rect: rect, to: target) ? "written" : "failed")")
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

private let popoverWindowProc: @convention(c) (HWND?, UINT, WPARAM, LPARAM) -> LRESULT = { hwnd, message, wParam, lParam in
    PopoverWindow.shared?.handle(hwnd, message, wParam, lParam) ?? DefWindowProcW(hwnd, message, wParam, lParam)
}
#endif

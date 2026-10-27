#if os(Windows)
import Foundation
import OpenUsageCore
import WinSDK

/// The Windows tray app: builds the dashboard model, shows the tray icon and popover, and refreshes on
/// the shared interval. The message loop runs here, cooperatively, so refresh tasks on the main actor
/// get their turns between messages.
package enum WindowsApp {
    @MainActor
    package static func run(arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment) async -> Int32 {
        let demo = arguments.contains("--demo")
        let showAtStart = arguments.contains("--show")
        SetProcessDPIAware()

        var mutex: HANDLE?
        if !demo {
            mutex = CreateMutexW(nil, false, Win32.wide("OpenUsageLightWindows"))
            if GetLastError() == DWORD(ERROR_ALREADY_EXISTS) { return 0 }
        }
        defer { if let mutex { CloseHandle(mutex) } }

        let model = demo ? DemoData.makeModel() : makeModel(environment: environment)
        let popover = PopoverWindow(model: model)
        PopoverWindow.shared = popover
        guard popover.create() else { return 1 }
        defer { popover.destroy() }

        var quit = false
        model.onChange = { popover.invalidate() }
        popover.onQuit = { quit = true }
        popover.onRefresh = { Task { await model.refresh(force: true) } }

        if showAtStart { popover.show() }
        var nextRefresh = Date()
        while !quit {
            var message = MSG()
            while PeekMessageW(&message, nil, 0, 0, UINT(PM_REMOVE)) {
                if message.message == UINT(WM_QUIT) { quit = true }
                TranslateMessage(&message)
                DispatchMessageW(&message)
            }
            if !demo, Date() >= nextRefresh {
                nextRefresh = Date().addingTimeInterval(RefreshSetting.interval)
                Task { await model.refresh() }
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return 0
    }

    @MainActor
    private static func makeModel(environment: [String: String]) -> DashboardModel {
        let directory = WindowsPaths.dataDirectory(environment: environment)
        let settings = FileSettingsStore(directory: directory.appendingPathComponent("settings", isDirectory: true))
        let vault = DPAPICredentialVault(directory: directory.appendingPathComponent("credentials", isDirectory: true))
        return DashboardModel(accounts: AccountStore(defaults: settings, vault: vault), settings: settings)
    }
}
#endif

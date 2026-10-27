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

        // `--snapshot <file.bmp>`: draw the popover off-screen to a picture and exit.
        if let flag = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(flag + 1) {
            let palette: PopoverPalette = arguments.contains("--dark") ? .dark : arguments.contains("--light") ? .light : .current()
            var screen = PopoverScreen.dashboard
            if let at = arguments.firstIndex(of: "--screen"), arguments.indices.contains(at + 1) {
                switch arguments[at + 1] {
                case "accounts": screen = .accounts
                case "picker": screen = .picker
                case "entry": screen = .entry(.openrouter)
                default: break
                }
            }
            let renderer = PopoverRenderer(
                sections: model.sections, palette: palette, dpi: Int(GetDpiForSystem()), status: "Updated just now",
                screen: screen, accounts: summaries(model)
            )
            return SnapshotWriter.write(renderer: renderer, to: URL(fileURLWithPath: arguments[flag + 1])) ? 0 : 1
        }
        let popover = PopoverWindow()
        popover.hidesWhenDeactivated = !showAtStart
        UIDebugLog.enabled = showAtStart
        UIDebugLog.write("session station=\(objectName(GetProcessWindowStation())) desktop=\(objectName(GetThreadDesktop(GetCurrentThreadId())))")

        // The window's thread draws from a snapshot of the model; every model change sends a new one.
        let publish: @MainActor () -> Void = {
            popover.update(PopoverState(
                sections: model.sections, isRefreshing: model.isRefreshing, lastRefreshed: model.lastRefreshed,
                accounts: Self.summaries(model)
            ))
        }
        model.onChange = publish
        publish()
        popover.onRefresh = { Task { @MainActor in await model.refresh(force: true) } }
        popover.onAddAccount = { kind, key in
            Task { @MainActor in
                model.accounts.add(kind: kind, label: kind.displayName, credential: .apiKey(key))
                model.reload()
                if !demo { await model.refresh(force: true) }
            }
        }
        popover.onRemoveAccount = { id in
            Task { @MainActor in
                model.accounts.remove(id)
                model.reload()
            }
        }

        // Refresh on the shared interval, concurrently with the window.
        let refresher = Task { @MainActor in
            while !Task.isCancelled {
                if !demo { await model.refresh() }
                try? await Task.sleep(for: .seconds(RefreshSetting.interval))
            }
        }
        let created = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let thread = Thread { continuation.resume(returning: popover.runMessageLoop(showAtStart: showAtStart)) }
            thread.name = "OpenUsage Light window"
            thread.stackSize = 4 << 20
            thread.start()
        }
        refresher.cancel()
        return created ? 0 : 1
    }

    /// The accounts in the dashboard's order, for the accounts page.
    @MainActor
    private static func summaries(_ model: DashboardModel) -> [AccountSummary] {
        model.sections.compactMap { section in
            model.accounts.accounts.first { $0.cardID == section.id }.map { AccountSummary(id: $0.id, kind: $0.kind, label: $0.label) }
        }
    }

    /// The name of a window station or desktop (a window shown on anything but the user's "WinSta0" is
    /// never seen by them).
    private static func objectName(_ handle: HANDLE?) -> String {
        guard let handle else { return "none" }
        var buffer = [WCHAR](repeating: 0, count: 256)
        var needed: DWORD = 0
        guard GetUserObjectInformationW(handle, Int32(UOI_NAME), &buffer, DWORD(buffer.count * 2), &needed) else { return "unknown" }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF16.self)
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

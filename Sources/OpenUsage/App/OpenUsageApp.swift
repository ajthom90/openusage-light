import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let processStartedAt = ProcessInfo.processInfo.systemUptime
    private var container: AppContainer?
    private var statusItemController: StatusItemController?
    private var singleInstanceLock: SingleInstanceLock.Token?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.bootstrap()
        if let bundleID = Bundle.main.bundleIdentifier {
            switch SingleInstanceLock.acquire(bundleIdentifier: bundleID) {
            case .acquired(let token):
                singleInstanceLock = token
            case .alreadyRunning:
                SingleInstanceGuard.activateExistingInstance()
                NSApp.terminate(nil)
                return
            case .failed(let message):
                AppLog.error(.lifecycle, "single-instance lock unavailable: \(message)")
            }
        }
        NSApp.disableRelaunchOnLogin()
        AppearanceSetting.applyCurrent()
        Task { await finishLaunching() }
    }

    private func finishLaunching() async {
        let container = await AppContainer()
        self.container = container
        startDashboard(container)
    }

    private func startDashboard(_ container: AppContainer) {
        container.startRefreshing()
        statusItemController = StatusItemController(container: container)
        let launchDurationMS = Int((ProcessInfo.processInfo.systemUptime - processStartedAt) * 1_000)
        AppLog.info(.lifecycle, "launch to status item ready: \(launchDurationMS) ms")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        container?.dataStore.flushPendingSnapshotWork()
    }
}

import OpenUsageMobile
import UIKit
import WidgetKit

/// Receives CloudKit's silent push when the Mac publishes, and refreshes the saved copy and the widgets.
final class AppDelegate: NSObject, UIApplicationDelegate {
    private var container: String? {
        Bundle.main.object(forInfoDictionaryKey: "ICloudContainer") as? String
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        let container = container
        Task { await BackgroundSync.subscribe(containerIdentifier: container) }
        return true
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        let changed = await BackgroundSync.refresh(containerIdentifier: container)
        if changed { WidgetCenter.shared.reloadAllTimelines() }
        return changed ? .newData : .noData
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        BackgroundSync.note("push registered \(Date())", topic: "registration")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        BackgroundSync.note("push registration failed: \(error.localizedDescription)", topic: "registration")
    }
}

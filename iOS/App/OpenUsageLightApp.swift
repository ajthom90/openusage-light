import OpenUsageMobile
import SwiftUI
import WidgetKit

@main
struct OpenUsageLightApp: App {
    @State private var model = MobileModel(
        containerIdentifier: Bundle.main.object(forInfoDictionaryKey: "ICloudContainer") as? String
    )

    var body: some Scene {
        WindowGroup {
            // `-widgetPreviews` draws every widget layout on one screen, for checking them without a Home Screen.
            if CommandLine.arguments.contains("-widgetPreviews") {
                WidgetPreviews()
            } else {
                DashboardScreen(model: model)
                    .onChange(of: model.generatedAt) { WidgetCenter.shared.reloadAllTimelines() }
            }
        }
    }
}

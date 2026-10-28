import OpenUsageMobile
import SwiftUI

@main
struct OpenUsageLightApp: App {
    @State private var model = MobileModel(
        containerIdentifier: Bundle.main.object(forInfoDictionaryKey: "ICloudContainer") as? String
    )

    var body: some Scene {
        WindowGroup {
            DashboardScreen(model: model)
        }
    }
}

import Foundation
import OpenUsageCore

/// The Mac app's sign-ins: the shared ones, with the Mac's own redirect listener for the browser ones.
enum ProviderLoginCatalog {
    static func login(for kind: ProviderKind) -> any ProviderLogin {
        SharedProviderLogins.login(for: kind, callbackServer: LoopbackCallbackServer.factory)!
    }
}

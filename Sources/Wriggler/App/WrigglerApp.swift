import SwiftUI
import UIKit

/// Locks the game to landscape on iPhone. The plist keys alone are not enough
/// there, so the delegate states it as well.
///
/// iPad is left open to every orientation: App Store Connect rejects an iPad app
/// that is landscape-only without also requiring full screen, which iOS 26 no
/// longer supports. The layout adapts, so iPad simply gets more room.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .landscape
    }
}

@main
struct WrigglerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

import UIKit

/// The SwiftUI launcher stays upright. The embedded GPU/gameplay surface
/// explicitly requests landscape and restores portrait on dismissal.
/// Supported masks must also be declared in Info.plist.
final class HorizonOrientationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?)
        -> UIInterfaceOrientationMask {
        HorizonOrientation.mask
    }
}

enum HorizonOrientation {
    static var mask: UIInterfaceOrientationMask = .portrait

    static func request(_ wanted: UIInterfaceOrientationMask) {
        guard mask != wanted else { return }
        mask = wanted
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                window.rootViewController?.presentedViewController?
                    .setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            if #available(iOS 16.0, *) {
                scene.requestGeometryUpdate(
                    UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: wanted)
                ) { error in
                    NSLog("Horizon: requested orientation could not be applied: %@", error.localizedDescription)
                }
            }
        }
    }
}

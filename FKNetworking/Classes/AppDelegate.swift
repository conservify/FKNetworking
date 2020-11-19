import Foundation

class AppDelegate: NSObject, UIApplicationDelegate {
    var backgroundCompletionHandler: (() -> Void)? = nil;
    
    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        NSLog("AppDelegate::did finish launching")
        return true
    }
    
    public func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        NSLog("AppDelegate::handleEventsForBackgroundURLSession %@", identifier)
        backgroundCompletionHandler = completionHandler
    }
}

import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Set before launch finishes so taps on reminders (even with the app closed) arrive here.
        UNUserNotificationCenter.current().delegate = NotificationHandler.shared
        Reminders.registerCategories()
        AppStore.shared.start()
        return true
    }
}

import Foundation
import UserNotifications

/// Handles reminder buttons ("Done", "In 1 hour", "I'm up"), including from the Lock Screen
/// while the app isn't open.
final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationHandler()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let itemText = info["item"] as? String
        let dayText = info["day"] as? String
        let slotText = info["slot"] as? String

        DispatchQueue.main.async {
            let store = AppStore.shared
            let itemID = itemText.flatMap { UUID(uuidString: $0) }
            let day = dayText.flatMap { Day(iso: $0) }
            let slot = slotText.flatMap { Int($0) }

            switch action {
            case Reminders.doneAction:
                if let itemID, let day {
                    store.complete(itemID, day: day, slot: slot, immediate: true)
                }
            case Reminders.laterAction:
                if let itemID, let day {
                    store.snooze(itemID, day: day, slot: slot, until: Date().addingTimeInterval(3600), immediate: true)
                }
            case Reminders.wakeAction:
                store.wakeUp(at: Date(), immediate: true)
            default:
                store.selectedTab = .today
                store.tick()
            }
            // Give the re-planned reminders a moment to be saved before iOS suspends the app.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                completionHandler()
            }
        }
    }
}

import SwiftUI
import UserNotifications

@main
struct VelaApp: App {
    @UIApplicationDelegateAdaptor(KiteAppDelegate.self) private var delegate

    init() { WazeWeb.install() }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}


final class KiteAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let value = response.notification.request.content.userInfo[TransitReminders.planKey] as? String,
              let id = UUID(uuidString: value) else { return }
        await MainActor.run { LaunchAction.shared.pendingTransit = id }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

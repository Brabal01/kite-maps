import Foundation
import UserNotifications
import VelaCore

struct SavedTransitPlan: Codable, Identifiable, Equatable {
    var id = UUID()
    let origin: Place
    let destination: Place
    let departure: Date
    let lines: [String]
    var reminder = false
    var name: String { "\(origin.name) → \(destination.name)" }
}

@MainActor
enum TransitReminders {
    nonisolated static let planKey = "savedTransitPlan"

    static func authorize() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default: return false
        }
    }

    static func schedule(_ plan: SavedTransitPlan) async -> Bool {
        let remaining = plan.departure.timeIntervalSinceNow
        guard remaining > 1, await authorize(), plan.departure.timeIntervalSinceNow > 1 else { return false }
        let wake = max(1, plan.departure.timeIntervalSinceNow - 300)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: wake, repeats: false)
        let content = UNMutableNotificationContent()
        content.title = "Time to leave"
        content.body = plan.name
        content.userInfo[planKey] = plan.id.uuidString
        content.sound = .default
        do {
            try await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: plan.id.uuidString, content: content, trigger: trigger))
            return true
        } catch { return false }
    }

    static func cancel(_ plan: SavedTransitPlan) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [plan.id.uuidString])
    }

    static func exit(stop: String, scheduled: Bool) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "Upcoming exit"
        content.body = scheduled ? "Scheduled exit coming up at \(stop)." : "Get off at the next stop, \(stop)."
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

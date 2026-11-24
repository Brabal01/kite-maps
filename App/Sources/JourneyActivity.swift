import ActivityKit
import Foundation
import UIKit

@available(iOS 16.2, *)
@MainActor
final class JourneyActivity {
    static let shared = JourneyActivity()
    private var current: Activity<TripActivity>?
    private var last: TripActivity.ContentState?
    private var lastUpdate = Date.distantPast

    private var lastCue: String?
    private var endingIDs: Set<String> = []

    func show(_ state: TripActivity.ContentState, cue: String?) {
        guard Bundle.main.object(forInfoDictionaryKey: "NSSupportsLiveActivities") as? Bool == true,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let now = Date()
        let shouldAlert = cue != nil && cue != lastCue && UIApplication.shared.applicationState == .background
        guard shouldAlert || state != last || now.timeIntervalSince(lastUpdate) > 40 else { return }
        guard shouldAlert || state.instruction != last?.instruction || now.timeIntervalSince(lastUpdate) >= 3 else { return }
        let content = ActivityContent(state: state, staleDate: now.addingTimeInterval(90))
        let sessions = Activity<TripActivity>.activities.filter { !endingIDs.contains($0.id) && ($0.activityState == .active || $0.activityState == .stale) }
        if let activity = sessions.first(where: { $0.id == current?.id }) ?? sessions.first {
            current = activity
            let alert: AlertConfiguration? = shouldAlert
                ? AlertConfiguration(title: "\(state.instruction)", body: "\(state.detail)", sound: .default) : nil
            if shouldAlert { lastCue = cue }
            Task { await activity.update(content, alertConfiguration: alert) }
        } else {
            guard UIApplication.shared.applicationState == .active else { return }
            current = try? Activity.request(attributes: TripActivity(), content: content)
        }
        if current != nil { last = state; lastUpdate = now }
    }

    func finish() {
        let sessions = Activity<TripActivity>.activities
        lastCue = nil
        endingIDs.formUnion(sessions.map(\.id))
        current = nil
        last = nil
        lastUpdate = .distantPast
        for activity in sessions {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
                endingIDs.remove(activity.id)
            }
        }
    }
}

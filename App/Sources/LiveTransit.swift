import ActivityKit
import Foundation
import UIKit
import VelaCore

@available(iOS 16.2, *)
@MainActor
final class LiveTransit {
    static let shared = LiveTransit()

    private typealias State = TransitActivityAttributes.ContentState
    private var current: Activity<TransitActivityAttributes>?
    private var last: State?
    private var refreshedAt = Date.distantPast

    func update(_ journey: TransitJourney) {
        guard let state = Self.state(journey), ActivityAuthorizationInfo().areActivitiesEnabled else {
            end()
            return
        }
        let now = Date()
        let content = ActivityContent(state: state, staleDate: now.addingTimeInterval(120))
        if let activity = current, activity.activityState == .active || activity.activityState == .stale {
            guard state != last || now.timeIntervalSince(refreshedAt) >= 60 else { return }
            Task { await activity.update(content) }
        } else {
            guard UIApplication.shared.applicationState == .active else { return }
            let previous = Activity<TransitActivityAttributes>.activities
            for activity in previous {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
            let attributes = TransitActivityAttributes(destination: journey.destination.name)
            current = try? Activity.request(attributes: attributes, content: content)
        }
        if current != nil {
            last = state
            refreshedAt = now
        }
    }

    func end() {
        let previous = Activity<TransitActivityAttributes>.activities
        let activity = current
        current = nil
        last = nil
        refreshedAt = .distantPast
        for item in previous where item.id != activity?.id {
            Task { await item.end(nil, dismissalPolicy: .immediate) }
        }
        if let activity { Task { await activity.end(nil, dismissalPolicy: .immediate) } }
    }

    private static func state(_ journey: TransitJourney) -> State? {
        guard let leg = journey.leg else { return nil }
        switch journey.phase {
        case .walk:
            let name = leg.toName.isEmpty || leg.toName == "END" ? journey.destination.name : leg.toName
            let transfer = journey.index == 0 ? "Walk to the stop" : "Walk to your connection"
            let title = journey.index + 1 == journey.trip.legs.count ? "Walk to destination" : transfer
            return State(symbol: "figure.walk", phase: title, detail: name, line: "", time: leg.arrive)
        case .board:
            let platform = leg.calls.first?.platform.map { "Platform \($0)" }
            let detail = [leg.fromName, platform].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            return State(symbol: "tram.fill", phase: leg.cancelled ? "Service cancelled" : "Board at the stop",
                         detail: detail, line: leg.line, time: leg.cancelled ? nil : leg.calls.first?.departure ?? leg.depart)
        case .ride:
            let next = journey.nextStop
            let exit = leg.toName
            let title = journey.exitWarning ? "Get ready to exit" : next.map { "Next · \($0.name)" } ?? "On the way"
            return State(symbol: journey.exitWarning ? "door.left.hand.open" : "tram.fill",
                         phase: title, detail: exit.isEmpty ? journey.destination.name : "Exit at \(exit)",
                         line: leg.line, time: journey.exitWarning ? leg.calls.last?.arrival ?? leg.arrive : next?.arrival)
        case .complete:
            return nil
        }
    }
}

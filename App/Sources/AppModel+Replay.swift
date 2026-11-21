import CoreLocation
import Foundation
import VelaCore

/**
 Developer GPS replay: plays a simulated drive along the route being navigated through the same path a
 real fix takes, so a roundabout, a tunnel or a late fix can be reproduced without driving.

 It is kept apart from real navigation on purpose: real fixes are ignored while it runs, nothing it
 produces is stored (no resumable trip, no Live Activity, no road-event lookups at made-up positions),
 and a banner says "Simulated GPS" for as long as it is on.
 */
extension AppModel {
    enum ReplayProfile {
        case clean
        /// Noise, a short tunnel and one late fix.
        case rough

        var title: String {
            switch self {
            case .clean: return "Clean drive"
            case .rough: return "Noisy GPS with a tunnel"
            }
        }
    }

    func startReplay(_ profile: ReplayProfile, speedFactor: Double = 1) {
        guard let n = nav, !isReplaying, transitJourney == nil else { return }
        let route = n.route
        let speed: Double = route.mode == .drive ? 13 : route.mode == .bike ? 4.5 : 1.4
        let fixture = GPSReplayFixture.drive(along: route.polyline, speed: speed, interval: 1, accuracy: 5,
                                             name: "Replay of the current route")
        var options = GPSReplayOptions()
        if profile == .rough {
            options.noiseMeters = 4
            let middle = fixture.duration / 2
            options.dropouts = [middle...(middle + 8)]
            options.lateRanges = [(middle + 20)...(middle + 21)]
            options.lateBySeconds = 3
        }
        let plan = GPSReplayPlan.schedule(fixture, options: options)
        guard !plan.isEmpty else { return }
        replayName = L10n.text(profile.title)
        let factor = max(1, speedFactor)
        let started = Date()
        replayTask = Task { [weak self] in
            var last = 0.0
            for step in plan {
                let wait = (step.deliverAt - last) / factor
                last = step.deliverAt
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                guard !Task.isCancelled, let self, self.nav === n else { break }
                // Timestamps follow the simulated clock, so a late fix really is older than the newest one.
                let stamp = started.addingTimeInterval(step.fix.t / factor)
                let fix = CLLocation(coordinate: CLLocationCoordinate2D(latitude: step.coordinate.lat, longitude: step.coordinate.lng),
                                     altitude: 0, horizontalAccuracy: step.fix.accuracy, verticalAccuracy: 5,
                                     course: step.fix.course, speed: step.fix.speed * factor, timestamp: stamp)
                self.locationChanged(fix, simulated: true)
            }
            guard let self else { return }
            self.replayName = nil
            self.replayTask = nil
        }
    }

    func stopReplay() {
        replayTask?.cancel()
        replayTask = nil
        replayName = nil
    }
}

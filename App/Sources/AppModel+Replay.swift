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

    func startReplay(_ fault: ReplaySession.Fault) {
        guard let n = nav, !isReplaying, transitJourney == nil else { return }
        let route = n.route
        let session = ReplaySession(route: route, fault: fault, onFix: { [weak self] step in
            guard let self, self.nav === n else { return }
            let fix = CLLocation(coordinate: CLLocationCoordinate2D(latitude: step.coordinate.lat, longitude: step.coordinate.lng),
                                 altitude: 0, horizontalAccuracy: step.fix.accuracy, verticalAccuracy: 5,
                                 course: step.fix.course, speed: max(0, step.fix.speed), timestamp: Date())
            self.locationChanged(fix, simulated: true)
        }, onFinish: { [weak self] in
            self?.stopReplay()
        })
        replaySession = session
        replayName = L10n.text(fault.title)
        session.start()
    }

    /// Older call sites (and the simulator smoke test) use the two named profiles.
    func startReplay(_ profile: ReplayProfile, speedFactor: Double = 1) {
        startReplay(profile == .clean ? .clean : .noise)
        replaySession?.speed = max(0.25, speedFactor)
    }

    func openReplayControls() { showDiagnostics = true }

    func pauseReplay() { replaySession?.pause() }
    func resumeReplay() { replaySession?.resume() }
    func skipToNextManeuver() {
        guard let session = replaySession, let maneuver = session.nextManeuverAfterProgress() else { return }
        if session.skip(to: maneuver.alongMeters) {
            notice = L10n.format("Replay jumped to: %@", maneuver.instruction)
        }
    }

    func setReplayOffline(_ offline: Bool) {
        replaySession?.simulateOffline = offline
        Connectivity.shared.setSimulatedOffline(offline)
    }

    func stopReplay() {
        replaySession?.stop()
        replaySession = nil
        replayName = nil
        Connectivity.shared.setSimulatedOffline(false)
    }
}

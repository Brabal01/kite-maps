import Foundation
import VelaCore

/// Presents a private replay tracker alongside the real navigator.
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
        let session = ReplaySession(route: n.route, fault: fault, onFinish: { [weak self] in
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
    }

    func stopReplay() {
        replaySession?.stop()
        replaySession = nil
        replayName = nil
    }
}

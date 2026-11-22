import Combine
import Foundation
import VelaCore

/**
 Drives a deterministic simulated GPS plan through the app. It owns its own clock and can be paused,
 slowed, sped up or skipped ahead; it never reads Core Location and it only calls back with simulated
 fixes, so it cannot be mistaken for a real position source.
 */
@MainActor
final class ReplaySession: ObservableObject {
    enum Fault: String, CaseIterable, Identifiable {
        case clean, noise, tunnel, lateFix, wrongTurn

        var id: String { rawValue }
        var title: String {
            switch self {
            case .clean: return "Clean"
            case .noise: return "GPS noise"
            case .tunnel: return "Tunnel (no fix)"
            case .lateFix: return "Late fix"
            case .wrongTurn: return "Wrong turn"
            }
        }
    }

    @Published var paused = false
    @Published var speed: Double = 1
    @Published var progress = 0.0
    @Published var note = ""
    @Published var simulateOffline = false
    @Published private(set) var instruction = ""
    private var tracker: RouteTracker

    let fault: Fault
    let route: Route
    let fixture: GPSReplayFixture
    private let plan: [ScheduledReplayFix]
    private let onFinish: () -> Void
    private var task: Task<Void, Never>?
    private var index = 0
    private var deliveredTime = 0.0

    init(route: Route, fault: Fault, onFinish: @escaping () -> Void) {
        self.route = route
        self.fault = fault
        tracker = RouteTracker(route: route)
        self.onFinish = onFinish
        let drive = GPSReplayFixture.drive(along: route.polyline,
                                           speed: route.mode == .drive ? 13 : route.mode == .bike ? 4.5 : 1.4,
                                           interval: 1, accuracy: 5, name: "Replay: \(fault.title)")
        var options = GPSReplayOptions()
        switch fault {
        case .noise:
            options.noiseMeters = 6
        case .tunnel:
            options.dropouts = [drive.duration * 0.35...(drive.duration * 0.35 + 12)]
        case .lateFix:
            options.lateRanges = [drive.duration * 0.5...(drive.duration * 0.5 + 3)]
            options.lateBySeconds = 4
        case .wrongTurn:
            options.poorRanges = [drive.duration * 0.45...(drive.duration * 0.45 + 8)]
            options.jumpMeters = 160
            options.poorAccuracy = 70
        case .clean:
            break
        }
        fixture = drive
        plan = GPSReplayPlan.schedule(drive, options: options)
    }

    var totalDuration: Double { fixture.duration }
    var isFinished: Bool { index >= plan.count }

    func start() {
        note = fault == .tunnel ? "A tunnel is simulated near the middle: GPS fixes stop briefly." : ""
        task = Task { [weak self] in
            while let self, !Task.isCancelled, index < plan.count {
                if paused {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    continue
                }
                let step = plan[index]
                let wait = max(0, step.deliverAt - deliveredTime) / max(0.25, speed)
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(min(wait, 30) * 1_000_000_000)) }
                guard !Task.isCancelled, !paused, step == plan[index] else { continue }
                deliveredTime = step.deliverAt
                index += 1
                progress = min(1, deliveredTime / max(1, totalDuration))
                let progress = tracker.update(step.coordinate, accuracy: max(5, step.fix.accuracy),
                                              heading: step.fix.course >= 0 ? step.fix.course : nil,
                                              speed: max(0, step.fix.speed), measured: !step.isLate)
                let maneuver = progress.nextIndex.flatMap { route.maneuvers.indices.contains($0) ? route.maneuvers[$0] : nil }
                instruction = maneuver?.spokenWords ?? ""
                if progress.offRoute {
                    note = simulateOffline ? "Off route. Simulated network is offline." : "Off route. Replay runs without a routing service."
                }
            }
            if let self, !Task.isCancelled { onFinish() }
        }
    }

    func pause() { paused = true }
    func resume() { paused = false }
    func stop() { task?.cancel(); task = nil }

    /** Jump to the first fix at or past [meters] along the route (a turn, an exit, a roundabout). */
    func skip(to meters: Double) -> Bool {
        guard !plan.isEmpty else { return false }
        let cumulative = Geo.cumulative(route.polyline)
        let wanted = max(0, meters)
        guard let target = plan.firstIndex(where: { Geo.project($0.coordinate, on: route.polyline, cumulative: cumulative).along >= wanted }) else { return false }
        tracker = RouteTracker(route: route)
        index = target
        deliveredTime = plan[target].deliverAt
        progress = min(1, deliveredTime / max(1, totalDuration))
        note = "Skipped to \(Int(wanted)) m along the route."
        return true
    }

    /** The next turn/exit the replay can jump to. */
    func nextManeuverAfterProgress() -> Maneuver? {
        let cumulative = Geo.cumulative(route.polyline)
        let here = index < plan.count ? Geo.project(plan[index].coordinate, on: route.polyline, cumulative: cumulative).along : 0
        return route.maneuvers.first { $0.alongMeters > here + 10 && $0.type != .arrive }
    }
}

import Foundation
import VelaCore

/// Road events (lights, stops, crossings) along the selected route, shared by the planner and its navigator.
/// Distances are relative to the selected route.
///
/// What is requested, and when, is decided by `RouteSectionScheduler`: a window ahead of the vehicle,
/// nearest section first, one request at a time, bounded retries with back-off and a circuit breaker.
/// Answers are reused through `RouteControlCache`, and mirrors that rate-limit us rest in `EndpointHealth`.
@MainActor
final class RouteEventCoverage {
    let routeID: UUID
    private(set) var events: [UpcomingRoadControl] = []
    /// Everything inside the look-ahead window has been answered.
    private(set) var complete = false
    /// Some section the vehicle needs could not be loaded (and is waiting for a retry or was given up on).
    private(set) var unavailable = false
    var changed: (() -> Void)?
    private var scheduler: RouteSectionScheduler
    private var worker: Task<Void, Never>?
    private let route: Route
    private let line: [LatLng]
    private let cumulative: [Double]

    init(_ route: Route) {
        self.route = route
        routeID = route.id
        line = route.polyline
        cumulative = Geo.cumulative(route.polyline)
        scheduler = RouteSectionScheduler(totalMeters: cumulative.last ?? 0)
        // The task holds the coverage only while a step runs, so dropping the coverage cancels it.
        worker = Task { [weak self] in
            while !Task.isCancelled {
                guard let next = await self?.step() else { return }
                switch next {
                case .working: continue
                case .finished: return
                case .wait(let seconds):
                    do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) } catch { return }
                }
            }
        }
    }

    private enum Step { case working, finished, wait(TimeInterval) }

    deinit { worker?.cancel() }

    /// The vehicle moved: sections it has passed are dropped from the plan and the window slides ahead.
    func updateProgress(_ alongMeters: Double) {
        scheduler.updateProgress(alongMeters)
        publishStatus(force: false)
    }

    private func step() async -> Step {
        guard let index = scheduler.next(now: Date()) else {
            if scheduler.isRouteLoaded {
                publishStatus(force: true)
                return .finished
            }
            return .wait(scheduler.nextWake(now: Date()).map { min(5, max(0.5, $0.timeIntervalSinceNow)) } ?? 3)
        }
        await load(index)
        return .working
    }

    private func load(_ index: Int) async {
        let range = scheduler.range(of: index)
        let total = cumulative.last ?? 0
        let start = range.lowerBound, end = range.upperBound
        let from = max(0, start - 40)
        let section = Geo.slice(line, from: from, to: min(total, end + 40), cumulative: cumulative)
        let walking = route.mode == .walk
        let key = RouteControlCache.key(for: section, walking: walking)
        var answer = RouteControlCache.shared.controls(for: key)
        if answer == nil {
            answer = await RouteControls.lookup(on: section, walking: walking)
            // An answer obtained while a mirror was resting may be partial; never keep it for later.
            if let answer, EndpointHealth.shared.available(Overpass.endpoints).count == Overpass.endpoints.count {
                RouteControlCache.shared.store(answer, for: key)
            }
        }
        guard !Task.isCancelled else {
            scheduler.cancelled(index)
            return
        }
        guard let answer else {
            scheduler.failed(index, now: Date(), wait: EndpointHealth.shared.secondsUntilAvailable(Overpass.endpoints))
            publishStatus(force: true)
            return
        }
        let distances = Geo.cumulative(section)
        let batch = answer.compactMap { event -> UpcomingRoadControl? in
            if route.mode == .drive && !event.kind.showsDuringDriving { return nil }
            let at = from + (event.alongMeters
                ?? Geo.project(event.location, on: section, cumulative: distances).along)
            guard at >= start, at < end || end == total else { return nil }
            var control = event
            control.alongMeters = at
            return UpcomingRoadControl(control: control, meters: at)
        }
        scheduler.succeeded(index)
        events.append(contentsOf: batch)
        events.sort { $0.meters < $1.meters }
        publishStatus(force: true)
    }

    private func publishStatus(force: Bool) {
        let nowComplete = scheduler.isWindowLoaded
        let nowUnavailable = scheduler.hasUnavailableSection
        let flagsChanged = nowComplete != complete || nowUnavailable != unavailable
        complete = nowComplete
        unavailable = nowUnavailable
        // Progress ticks arrive about once a second; only new data or a changed status reaches the views.
        if force || flagsChanged { changed?() }
    }
}

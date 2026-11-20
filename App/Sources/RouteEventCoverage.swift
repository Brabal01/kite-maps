import Foundation
import VelaCore

/// Shared by the planner and its navigator. Distances are relative to the selected route.
@MainActor
final class RouteEventCoverage {
    let routeID: UUID
    private(set) var events: [UpcomingRoadControl] = []
    private(set) var complete = false
    private(set) var unavailable = false
    var changed: (() -> Void)?
    private var worker: Task<Void, Never>?

    init(_ route: Route) {
        routeID = route.id
        worker = Task { [weak self] in
            let line = route.polyline
            let cumulative = Geo.cumulative(line)
            let total = cumulative.last ?? 0
            let size = 4000.0
            var pending = Array(0..<Int(ceil(total / size)))
            while !pending.isEmpty, !Task.isCancelled {
                var failed: [Int] = []
                for index in pending {
                    guard !Task.isCancelled else { return }
                    let start = Double(index) * size
                    let from = max(0, start - 40)
                    let end = min(total, start + size)
                    let section = Geo.slice(line, from: from, to: min(total, end + 40), cumulative: cumulative)
                    let result = await RouteControls.lookup(on: section, walking: route.mode == .walk)
                    guard let owner = self, !Task.isCancelled else { return }
                    if let result {
                        let distances = Geo.cumulative(section)
                        let batch = result.compactMap { event -> UpcomingRoadControl? in
                            if route.mode == .drive && !event.kind.showsDuringDriving { return nil }
                            let at = from + Geo.project(event.location, on: section, cumulative: distances).along
                            guard at >= start, at < end || end == total else { return nil }
                            return UpcomingRoadControl(control: event, meters: at)
                        }
                        owner.events.append(contentsOf: batch)
                        owner.events.sort { $0.meters < $1.meters }
                    } else { failed.append(index) }
                    owner.unavailable = !failed.isEmpty
                    owner.changed?()
                }
                pending = failed
                if !pending.isEmpty {
                    do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
                }
            }
            guard !Task.isCancelled else { return }
            self?.complete = true
            self?.changed?()
        }
    }
    deinit { worker?.cancel() }
}

import Foundation

/// Samples a short stretch of the selected route. A line that merely crosses it at an
/// intersection is allowed; a candidate that follows the stretch is not.
public struct RouteExclusion: Sendable {
    private let samples: [LatLng]

    public init?(near point: LatLng, on line: [LatLng]) {
        let cumulative = Geo.cumulative(line)
        let total = cumulative.last ?? 0
        guard total >= 60 else { return nil }
        let match = Geo.project(point, on: line, cumulative: cumulative)
        guard match.offset < 45, match.along > 25, match.along < total - 25 else { return nil }
        samples = [-22.0, 0, 22].map { Geo.point(along: line, meters: match.along + $0, cumulative: cumulative) }
    }

    public func allows(_ route: Route) -> Bool {
        guard route.polyline.count >= 2 else { return false }
        let cumulative = Geo.cumulative(route.polyline)
        let matched = samples.map { Geo.project($0, on: route.polyline, cumulative: cumulative) }
        return !zip(matched, matched.dropFirst()).contains { pair in
            pair.0.offset <= 16 && pair.1.offset <= 16 && abs(pair.0.along - pair.1.along) > 10
        }
    }
}

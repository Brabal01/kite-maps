import Foundation

public enum MapActivity: String, Equatable, Sendable {
    case browsing, freeDrive, navigatingDrive, navigatingWalk, navigatingBike
}

/**
 Traffic lights, stops and crossings have different value in each mode. A
 browsing map may show every crossing; guidance shows only infrastructure the
 driver is about to meet, and hides anything whose direction is unknown.
 */
public enum ControlDisplayPolicy {
    public static func shouldShow(_ control: RouteControl, activity: MapActivity,
                                  distanceAhead: Double?, directionCertain: Bool = true) -> Bool {
        let distance = distanceAhead ?? .infinity
        guard distance >= -20 else { return false }
        switch activity {
        case .browsing:
            return control.kind != .oneWay || distance < 500
        case .freeDrive:
            guard [.light, .stop, .railway].contains(control.kind) else { return false }
            return distance <= 350
        case .navigatingDrive:
            guard directionCertain else { return false }
            switch control.kind {
            case .light, .stop:
                return distance <= 450
            case .railway:
                return distance <= 600
            case .yield:
                return distance <= 180
            case .crossing, .tram, .oneWay:
                return false
            }
        case .navigatingWalk:
            switch control.kind {
            case .crossing, .light, .railway:
                return distance <= 500
            case .oneWay, .tram, .stop, .yield:
                return false
            }
        case .navigatingBike:
            switch control.kind {
            case .light, .crossing, .railway:
                return distance <= 500
            case .stop, .yield:
                return distance <= 180
            case .tram, .oneWay:
                return false
            }
        }
    }

    /** The nearest warning worth showing as a strip, without drawing every crossing on a street. */
    public static func upcoming(_ controls: [RouteControl], along: [LatLng],
                                activity: MapActivity, limit: Int = 4) -> [RouteControl] {
        guard along.count >= 2 else { return [] }
        let cumulative = Geo.cumulative(along)
        return controls.compactMap { control -> (RouteControl, Double)? in
            let match = Geo.project(control.location, on: along, cumulative: cumulative)
            guard shouldShow(control, activity: activity,
                             distanceAhead: match.along,
                             directionCertain: match.offset < 35) else { return nil }
            return (control, match.along)
        }
        .sorted { $0.1 < $1.1 }
        .prefix(limit)
        .map(\.0)
    }
}

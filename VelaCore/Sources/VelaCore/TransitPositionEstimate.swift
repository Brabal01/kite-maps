import Foundation

/// Positions from journey times are estimates, even when the times include live delays.
public enum TransitPositionEstimate {
    public static func location(on leg: TransitLeg, at now: Date) -> LatLng? {
        guard !leg.isWalk, leg.path.count >= 2, let departure = leg.depart, let arrival = leg.arrive,
              departure < arrival, (departure...arrival).contains(now) else { return nil }
        let line = leg.path
        let cumulative = Geo.cumulative(line)
        guard let length = cumulative.last, length > 0 else { return nil }
        var anchors = [(time: departure, distance: 0.0)]
        var floor = 0.0

        for call in leg.intermediateStops where !call.skipped {
            guard let point = call.location,
                  let time = call.arrival ?? call.departure,
                  time > anchors.last!.time, time < arrival else { continue }
            let remaining = Geo.slice(line, from: floor, to: length, cumulative: cumulative)
            guard remaining.count > 1 else { break }
            let projection = Geo.project(point, on: remaining)
            guard projection.offset <= 150 else { continue }
            floor = min(length, floor + projection.along)
            anchors.append((time, floor))
            if let leave = call.departure, leave > time, leave < arrival {
                anchors.append((leave, floor))
            }
            if time >= now || anchors.last!.time >= now { break }
        }
        anchors.append((arrival, length))

        guard let next = anchors.dropFirst().firstIndex(where: { $0.time >= now }) else { return nil }
        let start = anchors[next - 1], end = anchors[next]
        let fraction = now.timeIntervalSince(start.time) / end.time.timeIntervalSince(start.time)
        return Geo.point(along: line, meters: start.distance + (end.distance - start.distance) * fraction,
                         cumulative: cumulative)
    }
}

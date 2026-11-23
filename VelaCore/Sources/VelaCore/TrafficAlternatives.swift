import Foundation

public enum TrafficAlternatives {
    /// Transfer refreshed traffic to the same roadway without replacing the active route or tracker.
    public static func reprojectSpans(from update: Route, onto remaining: [LatLng], startingAt offset: Double) -> [TrafficSpan] {
        guard update.polyline.count >= 2, remaining.count >= 2, offset.isFinite, offset >= 0 else { return [] }
        let source = Geo.cumulative(update.polyline)
        let target = Geo.cumulative(remaining)
        guard let sourceLength = source.last, let targetLength = target.last,
              sourceLength.isFinite, targetLength.isFinite, targetLength > 0 else { return [] }
        return update.trafficSpans.compactMap { span in
            let end = min(sourceLength, span.startMeters + span.lengthMeters)
            guard span.startMeters >= 0, end > span.startMeters, (1...3).contains(span.level) else { return nil }
            let samples = [span.startMeters, (span.startMeters + end) / 2, end].map { distance in
                Geo.project(Geo.point(along: update.polyline, meters: distance, cumulative: source),
                            on: remaining, cumulative: target)
            }
            let a = samples[0], middle = samples[1], b = samples[2]
            guard samples.allSatisfy({ $0.offset <= 30 }),
                  a.along <= middle.along, middle.along <= b.along, b.along > a.along else { return nil }
            return TrafficSpan(level: span.level, startMeters: offset + a.along, lengthMeters: b.along - a.along)
        }
    }

    /// Both durations refer to the same departure position, even if the car moves during the request.
    public static func compare(_ routes: [Route], on original: [LatLng], previousETA: Double)
        -> (currentETA: Double?, alternative: Route?, saving: Double) {
        var current: Double?
        var alternative: Route?
        for route in routes {
            guard let seconds = route.trafficSeconds, seconds.isFinite, seconds > 0, route.polyline.count > 1 else { continue }
            if Geo.isNearRoute(route.polyline, reference: original) && Geo.isNearRoute(original, reference: route.polyline) {
                current = min(current ?? seconds, seconds)
            } else if seconds < (alternative?.durationSeconds ?? .infinity) {
                alternative = route
            }
        }
        let baseline = current ?? previousETA
        let saving = baseline - (alternative?.durationSeconds ?? baseline)
        return (current, saving > max(60, baseline * 0.05) ? alternative : nil, saving)
    }
}

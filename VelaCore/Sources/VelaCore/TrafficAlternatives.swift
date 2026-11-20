import Foundation

public enum TrafficAlternatives {
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

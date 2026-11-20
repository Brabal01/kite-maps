import Foundation

/**
 Route alternatives, filtered so two answers that are effectively the same road
 are not presented as a choice.

 Routers often return a "second" route that differs by a few seconds and a few
 hundred metres; the trip sheet then makes the driver compare two identical
 cards. The filter keeps the fastest route and only keeps another when it is
 meaningfully different in time or distance. It never invents or reranks a
 route, and it never drops a route for being slower alone: a longer but clearly
 different road stays available.
 */
public enum RouteAlternatives {
    /**
     - Parameters:
       - routes: candidates, in any order.
       - minimumSeconds: below this difference, two routes are the same choice.
       - minimumMeters: below this distance difference, likewise.
     */
    public static func distinct(_ routes: [Route],
                                minimumSeconds: Double = 45,
                                minimumMeters: Double = 250) -> [Route] {
        guard routes.count > 1 else { return routes }
        let sorted = routes.sorted { $0.durationSeconds < $1.durationSeconds }
        var kept: [Route] = []
        for route in sorted {
            let duplicate = kept.contains { other in
                let seconds = abs(route.durationSeconds - other.durationSeconds)
                let meters = abs(route.distanceMeters - other.distanceMeters)
                // On a long trip a 45 s difference is noise, so the tolerance grows with
                // the trip but stays bounded by what a driver would actually notice.
                let allowedSeconds = max(minimumSeconds, min(other.durationSeconds * 0.03, 180))
                let allowedMeters = max(minimumMeters, min(other.distanceMeters * 0.03, 3_000))
                return seconds <= allowedSeconds && meters <= allowedMeters
            }
            if !duplicate { kept.append(route) }
        }
        return kept
    }
}

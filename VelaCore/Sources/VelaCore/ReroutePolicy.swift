import Foundation

/**
 * When leaving the route is real enough to ask for a new one. Kept in VelaCore so the dangerous
 * cases (a noisy fix, a car park, a tunnel, a fix beside a parallel road) can be tested without
 * an iPhone or a live router.
 */
public enum ReroutePolicy {
    public static func shouldReroute(offsetMeters: Double, accuracy: Double, speed: Double,
                                     offRouteFixes: Int, joinedRoute: Bool, nearDestination: Bool,
                                     secondsSinceLast: Double, departureEvidence: Double) -> Bool {
        guard joinedRoute || offsetMeters > max(100, accuracy * 3) else { return false }
        guard !nearDestination, secondsSinceLast > 3 else { return false }
        guard accuracy >= 0, accuracy <= 60 else { return false }
        let corridor = max(24, accuracy * 1.6 + min(max(speed, 0) * 0.35, 12))
        guard offsetMeters > corridor else { return false }
        // Evidence is about the fix being off the road, not about the map match confidence. A weak
        // match far off the road is still a departure; a weak match near a parallel road is not.
        guard departureEvidence >= 0.3 else { return false }
        // More confirmation as accuracy gets worse, but the tracker counter keeps counting past 3.
        let required = accuracy <= 45 ? 3 : 4
        return offRouteFixes >= required
    }
}

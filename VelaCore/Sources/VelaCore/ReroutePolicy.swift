import Foundation

/**
 * When leaving the route is real enough to ask for a new one. Kept in VelaCore so the dangerous
 * cases (a noisy fix, a car park, a tunnel, a fix beside a parallel road) can be tested without
 * an iPhone or a live router.
 */
public enum ReroutePolicy {
    public static func shouldReroute(offsetMeters: Double, accuracy: Double, speed: Double,
                                     offRouteFixes: Int, joinedRoute: Bool, nearDestination: Bool,
                                     secondsSinceLast: Double, confidence: Double) -> Bool {
        guard joinedRoute || offsetMeters > max(100, accuracy * 3) else { return false }
        guard !nearDestination, secondsSinceLast > 3, confidence >= 0.2 else { return false }
        guard accuracy >= 0, accuracy <= 60 else { return false }
        let corridor = max(24, accuracy * 1.6 + min(max(speed, 0) * 0.35, 12))
        guard offsetMeters > corridor else { return false }
        // A noisier fix must be confirmed more often; four precise-looking fixes in a row can still
        // be a car park or a bridge, so keep the same guard for both.
        let required = accuracy <= 30 ? 3 : 4
        return offRouteFixes >= required
    }
}

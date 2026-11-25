import Foundation

/**
 * When leaving the route is real enough to ask for a new one. Kept in VelaCore so the dangerous
 * cases (a noisy fix, a car park, a tunnel, a fix beside a parallel road) can be tested without
 * an iPhone or a live router.
 */
public enum ReroutePolicy {
    static func corridor(mode: TravelMode, accuracy: Double, speed: Double) -> Double {
        let floor = mode == .drive ? 24.0 : mode == .bike ? 18.0 : 14.0
        return max(floor, accuracy * 1.6 + min(max(speed, 0) * 0.35, 12))
    }

    static func requiredFixes(mode: TravelMode, accuracy: Double) -> Int {
        if mode == .walk { return accuracy <= 18 ? 2 : 3 }
        return accuracy <= 45 ? 3 : 4
    }

    public static func shouldReroute(offsetMeters: Double, accuracy: Double, speed: Double,
                                     offRouteFixes: Int, joinedRoute: Bool, nearDestination: Bool,
                                     secondsSinceLast: Double, departureEvidence: Double,
                                     mode: TravelMode = .drive) -> Bool {
        if mode == .walk {
            guard joinedRoute || offsetMeters > max(40, accuracy * 2.3) else { return false }
            guard !nearDestination, secondsSinceLast > 2, (0...35).contains(accuracy) else { return false }
            guard offsetMeters > corridor(mode: .walk, accuracy: accuracy, speed: speed),
                  departureEvidence >= 0.25 else { return false }
            return offRouteFixes >= requiredFixes(mode: .walk, accuracy: accuracy)
        }
        guard joinedRoute || offsetMeters > max(100, accuracy * 3) else { return false }
        guard !nearDestination, secondsSinceLast > 3 else { return false }
        guard accuracy >= 0, accuracy <= 60 else { return false }
        let corridor = max(24, accuracy * 1.6 + min(max(speed, 0) * 0.35, 12))
        guard offsetMeters > corridor else { return false }
        // Evidence is about the fix being off the road, not about the map match confidence. A weak
        // match far off the road is still a departure; a weak match near a parallel road is not.
        guard departureEvidence >= 0.3 else { return false }
        // More confirmation as accuracy gets worse, but the tracker counter keeps counting past 3.
        let required = requiredFixes(mode: mode, accuracy: accuracy)
        return offRouteFixes >= required
    }
}

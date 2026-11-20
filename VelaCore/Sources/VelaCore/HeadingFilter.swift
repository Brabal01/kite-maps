import Foundation

/** Heading arithmetic shared by the map arrow and the compass: shortest way round, no 359→0 jump. */
public enum HeadingFilter {
    public static func normalized(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 360)
        return result < 0 ? result + 360 : result
    }

    /** Signed difference from [from] to [to], in -180..<180: 350 → 10 is +20, not -340. */
    public static func shortestDelta(from: Double, to: Double) -> Double {
        (normalized(to) - normalized(from) + 540).truncatingRemainder(dividingBy: 360) - 180
    }

    /**
     * Follows [raw] without letting compass noise twitch the arrow. A larger [dt] trusts the new
     * reading more; 60 Hz compass updates average heavily, 1 Hz GPS fixes follow quickly.
     */
    public static func smooth(previous: Double?, raw: Double, dt: Double) -> Double {
        let raw = normalized(raw)
        guard let previous else { return raw }
        let seconds = max(0.02, min(1.0, dt))
        let alpha = 1 - exp(-seconds * 6)
        return normalized(previous + shortestDelta(from: previous, to: raw) * alpha)
    }
}

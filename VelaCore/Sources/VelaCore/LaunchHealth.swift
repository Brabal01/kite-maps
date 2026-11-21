import Foundation

/**
 Decides when Kite should offer safe mode after launch trouble, without ever trapping the user in a loop.

 A launch counts as *unhealthy* when it never reached the ready state (a healthy screen for about ten
 seconds) and never went to the background cleanly. Swiping the app away or locking the phone right after
 opening it is a normal exit, not a crash, so it clears the marker. Safe mode is entered only after
 `threshold` unhealthy launches in a row inside `window`, and entering it resets the counter, so the next
 launch after the user leaves safe mode starts from zero.
 */
public struct LaunchHealth: Codable, Equatable, Sendable {
    public var consecutiveUnhealthy = 0
    /** Set at launch, cleared when the launch proved healthy or exited cleanly. */
    public var pendingSince: Date?

    public init(consecutiveUnhealthy: Int = 0, pendingSince: Date? = nil) {
        self.consecutiveUnhealthy = consecutiveUnhealthy
        self.pendingSince = pendingSince
    }

    public static let threshold = 2
    public static let window: TimeInterval = 10 * 60

    /** Call once per launch. Returns whether this launch should start in safe mode. */
    public mutating func launch(now: Date = Date(), threshold: Int = LaunchHealth.threshold,
                                window: TimeInterval = LaunchHealth.window) -> Bool {
        if let pending = pendingSince {
            if now.timeIntervalSince(pending) < window { consecutiveUnhealthy += 1 } else { consecutiveUnhealthy = 1 }
        } else {
            consecutiveUnhealthy = 0
        }
        if consecutiveUnhealthy >= threshold {
            consecutiveUnhealthy = 0
            pendingSince = nil
            return true
        }
        pendingSince = now
        return false
    }

    /** The launch reached a healthy screen, or went to the background without crashing. */
    public mutating func markHealthy() {
        pendingSince = nil
        consecutiveUnhealthy = 0
    }
}

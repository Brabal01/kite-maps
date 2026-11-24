import Foundation

public enum NavigationCamera {
    public static func reliableFix(age: TimeInterval, accuracy: Double) -> Bool {
        (0...5).contains(age) && (0...45).contains(accuracy)
    }

    public static func reanchor(firstReliableFix: Bool, displacement: Double, accuracy: Double) -> Bool {
        firstReliableFix && displacement > max(45, accuracy * 2)
    }

    public static func snappedToRoute(mode: TravelMode, offset: Double, offRoute: Bool) -> Bool {
        !offRoute && offset < (mode == .walk ? 14 : 40)
    }

    public static func shortestTurn(from: Double, to: Double) -> Double {
        ((to - from + 540).truncatingRemainder(dividingBy: 360)) - 180
    }

    public static func padding(height: Double) -> (top: Double, bottom: Double) {
        let bottom = min(170, height * 0.34)
        let viewport = min(height, max(48, height * 0.10))
        return (min(height * 0.70, max(0, height - bottom - viewport)), bottom)
    }

    public struct FollowControls {
        public private(set) var zoomSteps = 0
        private var closeUntil: TimeInterval = 0
        private var lastCenter: LatLng?

        public init() {}

        public mutating func begin(at now: TimeInterval) {
            self = Self()
            closeUntil = now + 10
        }

        public mutating func recenter(at now: TimeInterval) {
            closeUntil = now + 10
        }

        public mutating func tapLocation(_ position: LatLng, following: Bool, at now: TimeInterval) {
            if following, let lastCenter, lastCenter.distance(to: position) < 18 {
                zoomSteps = max(zoomSteps, 5)
            }
            lastCenter = position
            recenter(at: now)
        }

        public mutating func zoom(by steps: Int) {
            zoomSteps = min(10, max(-4, zoomSteps + steps))
        }

        public func distance(_ across: Double, scale: Double, mode: TravelMode, at now: TimeInterval) -> Double {
            let base = mode == .drive && now < closeUntil ? min(across, 350 * scale) : across
            return base / pow(1.36, Double(zoomSteps))
        }
    }
}

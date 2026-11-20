import Foundation

/**
 * Follows the driver along a route: snaps each GPS fix to the line, says how far the next
 * maneuver is, how much trip is left, and when the driver has left the route.
 *
 * The match is not just "the nearest point": it weighs the fix's accuracy, the direction the
 * vehicle is actually moving, how far it could have travelled since the last fix, and the road's
 * own bearing. That keeps the arrow on the flyover instead of jumping to the service road below,
 * and on the correct carriageway instead of the opposite one. When the fix is too poor to trust,
 * the tracker keeps the last good progress and reports low confidence instead of pretending the
 * position is precise.
 */
public final class RouteTracker {
    public struct Progress: Sendable {
        public var snapped: LatLng
        public var alongMeters: Double
        /** How far the fix is from the line. */
        public var offsetMeters: Double
        /** Bearing of the route at the snapped point. */
        public var routeBearing: Double
        public var nextIndex: Int?
        public var distanceToNext: Double
        public var remainingMeters: Double
        public var remainingSeconds: Double
        public var offRoute: Bool
        public var arrived: Bool
        /** How much the map match can be trusted, 0…1. */
        public var confidence: Double
        /** True when the fix itself is good enough to present as a measured position. */
        public var isPrecise: Bool
        /** Consecutive measured fixes outside the corridor (0…3), for a guarded reroute decision. */
        public var offRouteFixes: Int
    }

    public let route: Route
    private let cum: [Double]
    private let total: Double
    private let segmentBearings: [Double]
    private var segment = 0
    private var offCount = 0
    private var wrongWayCount = 0

    /** Last accepted match, for dead reckoning and for choosing the right parallel road. */
    private var lastAlong: Double?
    private var lastUpdate: Date?
    private var lastMatchedAt = Date.distantPast
    private var lastHeading: Double?

    public static func isFreshFix(age: Double, accuracy: Double, maximumError: Double) -> Bool {
        (-2...8).contains(age) && (0...maximumError).contains(accuracy)
    }

    public init(route: Route) {
        self.route = route
        cum = Geo.cumulative(route.polyline)
        total = cum.last ?? 0
        segmentBearings = (0..<max(0, route.polyline.count - 1)).map {
            Geo.bearing(route.polyline[$0], route.polyline[$0 + 1])
        }
    }

    /**
     * [heading] is the way the car is moving (degrees from north), only when it's moving fast enough
     * for the phone's compass course to mean something.
     */
    public func update(_ fix: LatLng, accuracy: Double = 10, heading: Double? = nil, speed: Double = 0,
                       measured: Bool = true, now: Date = Date()) -> Progress {
        let line = route.polyline
        guard line.count >= 2 else {
            return Progress(snapped: fix, alongMeters: 0, offsetMeters: .greatestFiniteMagnitude,
                            routeBearing: 0, nextIndex: nil, distanceToNext: 0, remainingMeters: 0,
                            remainingSeconds: 0, offRoute: false, arrived: false,
                            confidence: 0, isPrecise: false, offRouteFixes: 0)
        }
        let dt = lastUpdate.map { max(0, min(5, now.timeIntervalSince($0))) } ?? 0
        let expected = max(0, speed) * dt
        let all = lastAlong == nil
        let from = all ? 0 : max(0, segment - 8)
        let to = all ? line.count - 2 : min(line.count - 2, segment + 80)
        var best = candidate(fix, from: from, to: to, heading: heading, expected: expected)
        if !all, best.offset > 70 {
            let everywhere = candidate(fix, from: 0, to: line.count - 2, heading: heading, expected: expected)
            // Only leave the local window when the whole-route match is clearly better and is not
            // just a parallel road with a conflicting direction.
            if everywhere.score + 18 < best.score { best = everywhere }
        }
        segment = best.segment
        var along = cum[best.segment] + best.t * (cum[best.segment + 1] - cum[best.segment])
        var snapped = LatLng(line[best.segment].lat + (line[best.segment + 1].lat - line[best.segment].lat) * best.t,
                             line[best.segment].lng + (line[best.segment + 1].lng - line[best.segment].lng) * best.t)
        var offset = best.offset
        var confidence = best.confidence

        let floor = route.mode == .drive ? 24.0 : route.mode == .bike ? 18.0 : 14.0
        let limit = max(floor, accuracy * 1.6 + min(max(speed, 0) * 0.35, 12))

        // A precise fix far outside the corridor is enough; near the edge require confirmation.
        if measured {
            if accuracy > 60 {
                offCount = 0 // A very poor fix is no evidence at all.
            } else if offset > max(limit * 2, 35) {
                // A precise fix clearly outside the corridor is evidence enough for the tracker;
                // the reroute decision still needs the confidence check in ReroutePolicy. A noisier
                // fix increments one step at a time.
                offCount = accuracy <= 25 ? 3 : min(3, offCount + 1)
            } else if offset > limit {
                offCount = min(3, offCount + 1)
            } else {
                offCount = 0
            }
        }

        // A short signal gap, or a fix beside a bridge/tunnel/parallel road: keep moving along the
        // last good match instead of teleporting onto the nearest piece of tarmac.
        let recentMatch = now.timeIntervalSince(lastMatchedAt) < 6 && dt < 4
        let jump = lastAlong.map { abs(along - $0) } ?? 0
        let uncertain = offset > limit || (lastAlong != nil && jump > max(250, expected * 3 + 80))
        if measured, recentMatch, let previous = lastAlong, uncertain, speed > 1 {
            let advanced = min(total, previous + expected)
            if advanced >= previous {
                along = advanced
                snapped = Geo.point(along: line, meters: along, cumulative: cum)
                offset = fix.distance(to: snapped)
                confidence = 0.15
                segment = segment(near: along)
            }
        }

        let routeBearing = segmentBearings.isEmpty ? 0 : segmentBearings[min(segment, segmentBearings.count - 1)]
        // The road's way over about 30 m, so a tiny kink or doubled point in the line isn't "backwards".
        let a = Geo.point(along: line, meters: max(0, along - 10), cumulative: cum)
        let b = Geo.point(along: line, meters: min(total, along + 20), cumulative: cum)
        let roadBearing = a.distance(to: b) > 5 ? Geo.bearing(a, b) : routeBearing
        if measured, let heading, offset <= limit, roadBearing.isFinite {
            let diff = abs(HeadingFilter.shortestDelta(from: roadBearing, to: heading))
            wrongWayCount = diff > 120 ? wrongWayCount + 1 : 0
        } else if measured {
            wrongWayCount = 0
        }

        let next = route.maneuvers.firstIndex { !$0.silent && $0.alongMeters > along + 8 }
        let toNext = next.map { route.maneuvers[$0].alongMeters - along } ?? (total - along)
        let remaining = max(0, total - along)
        let precise = measured && accuracy <= 25 && offset <= 25 && confidence >= 0.55
        lastAlong = along
        lastUpdate = now
        lastHeading = heading
        if measured, offset <= limit, confidence >= 0.3 { lastMatchedAt = now }

        return Progress(
            snapped: snapped,
            alongMeters: along,
            offsetMeters: offset,
            routeBearing: routeBearing,
            nextIndex: next,
            distanceToNext: max(0, toNext),
            remainingMeters: remaining,
            remainingSeconds: route.remainingSeconds(from: along),
            offRoute: offCount >= 3 || wrongWayCount >= 4,
            // Only on the road to it: passing close by on a parallel street isn't arriving.
            arrived: remaining < 25 && offset < limit,
            confidence: confidence,
            isPrecise: precise,
            offRouteFixes: offCount
        )
    }

    private struct Candidate {
        var segment: Int
        var t: Double
        var offset: Double
        var score: Double
        var confidence: Double
    }

    private func candidate(_ p: LatLng, from: Int, to: Int, heading: Double?, expected: Double) -> Candidate {
        let line = route.polyline
        guard from <= to else { return Candidate(segment: 0, t: 0, offset: .greatestFiniteMagnitude, score: .greatestFiniteMagnitude, confidence: 0) }
        let k = cos(p.lat * .pi / 180) * 111_320.0
        var best: Candidate?
        for i in from...to {
            let a = line[i], b = line[i + 1]
            let ax = (a.lng - p.lng) * k, ay = (a.lat - p.lat) * 110_540
            let bx = (b.lng - p.lng) * k, by = (b.lat - p.lat) * 110_540
            let dx = bx - ax, dy = by - ay
            let len2 = dx * dx + dy * dy
            let t = len2 > 0 ? min(max(-(ax * dx + ay * dy) / len2, 0), 1) : 0
            let x = ax + t * dx, y = ay + t * dy
            let distance = (x * x + y * y).squareRoot()
            let along = cum[i] + t * (cum[i + 1] - cum[i])
            var cost = distance
            var directionPenalty = 0.0
            if let heading, i < segmentBearings.count, a.distance(to: b) > 8 {
                let diff = abs(HeadingFilter.shortestDelta(from: segmentBearings[i], to: heading))
                if diff > 135 {
                    directionPenalty = 55
                } else {
                    directionPenalty = diff * 0.18
                }
                cost += directionPenalty
            }
            if let previous = lastAlong {
                // Prefer a match near where the vehicle can have reached since the last fix.
                let wanted = previous + expected
                cost += min(50, abs(along - wanted) * 0.08)
                if along < previous - 20 { cost += 25 }
            }
            let confidence = max(0, min(1, 1 - distance / 85 - directionPenalty / 90))
            if cost < (best?.score ?? .greatestFiniteMagnitude) {
                best = Candidate(segment: i, t: t, offset: distance, score: cost, confidence: confidence)
            }
        }
        return best ?? Candidate(segment: from, t: 0, offset: .greatestFiniteMagnitude,
                                 score: .greatestFiniteMagnitude, confidence: 0)
    }

    private func segment(near along: Double) -> Int {
        guard route.polyline.count >= 2 else { return 0 }
        var lo = 0, hi = cum.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if cum[mid] >= along { hi = mid } else { lo = mid + 1 }
        }
        return max(0, min(route.polyline.count - 2, lo == 0 ? 0 : lo - 1))
    }
}

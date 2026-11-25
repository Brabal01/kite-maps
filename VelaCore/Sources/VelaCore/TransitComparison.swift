import Foundation

public enum TransitComparison {
    public struct Segment: Equatable, Sendable {
        public enum Kind: Equatable, Sendable { case walk, wait, ride }
        public let kind: Kind
        public let leg: Int?
        public let offset: TimeInterval
        public let duration: TimeInterval
    }

    public enum Preference: String, CaseIterable, Identifiable, Sendable {
        case recommended = "Recommended"
        case fastest = "Fastest"
        case fewestTransfers = "Fewest changes"
        case leastWalking = "Least walking"
        case safestTransfers = "Most transfer time"

        public var id: String { rawValue }
    }

    public enum Risk: Int, Comparable, Sendable {
        case low, tight, high

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public struct Transfer: Equatable, Sendable {
        public let outgoingLeg: Int
        public let spareSeconds: TimeInterval
        public let risk: Risk
    }

    public static func timeline(for trip: TransitTrip) -> [Segment] {
        let origin = trip.depart ?? trip.legs.compactMap(\.depart).first
        var cursor: TimeInterval = 0
        var segments: [Segment] = []
        for (index, leg) in trip.legs.enumerated() {
            let depart = origin.flatMap { start in leg.depart?.timeIntervalSince(start) } ?? cursor
            let start = max(cursor, depart)
            if start > cursor {
                segments.append(Segment(kind: .wait, leg: nil, offset: cursor, duration: start - cursor))
            }
            let arrive = origin.flatMap { start in leg.arrive?.timeIntervalSince(start) }
            let end = arrive ?? (start + leg.durationSeconds)
            cursor = max(start, end)
            if cursor > start {
                segments.append(Segment(kind: leg.isWalk ? .walk : .ride, leg: index,
                                        offset: start, duration: cursor - start))
            }
        }
        return segments
    }

    public static func transfers(for trip: TransitTrip, walkingSpeedKmh: Double) -> [Transfer] {
        let rides = trip.legs.indices.filter { !trip.legs[$0].isWalk }
        let speed = min(9, max(1, walkingSpeedKmh))
        return zip(rides, rides.dropFirst()).compactMap { from, to in
            guard let arrive = trip.legs[from].arrive, let depart = trip.legs[to].depart else { return nil }
            let walk = trip.legs[(from + 1)..<to].reduce(0.0) { seconds, leg in
                seconds + (leg.distanceMeters > 0 ? leg.distanceMeters * 3.6 / speed : max(0, leg.durationSeconds))
            }
            let spare = depart.timeIntervalSince(arrive) - max(60, walk)
            let risk: Risk = spare < 0 ? .high : spare < 120 ? .tight : .low
            return Transfer(outgoingLeg: to, spareSeconds: spare, risk: risk)
        }
    }

    public static func rankedIndices(_ trips: [TransitTrip], by preference: Preference,
                                     walkingSpeedKmh: Double) -> [Int] {
        let scores = trips.map { trip -> (primary: Double, duration: Double) in
            let duration = max(0, trip.durationSeconds)
            let connections = transfers(for: trip, walkingSpeedKmh: walkingSpeedKmh)
            let walking = trip.walkSeconds
            let worst = connections.map(\.risk).max() ?? .low
            let primary: Double
            switch preference {
            case .fastest: primary = duration
            case .fewestTransfers: primary = Double(trip.transfers)
            case .leastWalking: primary = walking
            case .safestTransfers:
                primary = trip.transfers == 0 ? -.infinity
                    : -(connections.map(\.spareSeconds).min() ?? -.infinity)
            case .recommended:
                let waiting = timeline(for: trip).filter { $0.kind == .wait }.reduce(0) { $0 + $1.duration }
                let riskCost: Double = worst == .high ? 1_800 : worst == .tight ? 420 : 0
                let unknownCost = connections.count < trip.transfers ? 180.0 : 0
                primary = duration + Double(trip.transfers) * 240 + walking * 0.45 + waiting * 0.25 + riskCost + unknownCost
            }
            return (primary, duration)
        }
        return trips.indices.sorted { a, b in
            (scores[a].primary, scores[a].duration, a) < (scores[b].primary, scores[b].duration, b)
        }
    }
}

import Foundation

public enum LaneUse: String, Equatable, Sendable {
    case recommended, suitable, unsuitable, unknown
}

public struct GuidedLane: Equatable, Sendable {
    public var indications: [String]
    public var use: LaneUse

    public init(indications: [String], use: LaneUse) {
        self.indications = indications
        self.use = use
    }
}

/** Why the lanes are up: a turn, a straight approach, a split/merge or a roundabout. */
public enum LaneGuidanceKind: String, Equatable, Sendable {
    case turn, straight, motorwayExit, merge, split, roundabout
}

public struct LaneGuidance: Equatable, Sendable {
    public var lanes: [GuidedLane]
    public var kind: LaneGuidanceKind
    public var title: String
    public var detail: String
    public var showEarly: Bool
    public var confidence: Double

    public var recommended: [Int] { lanes.indices.filter { lanes[$0].use == .recommended } }
    public var hasUnknown: Bool { lanes.contains { $0.use == .unknown } }
}

/**
 Lane Guidance 3.0.

 The router's own lane list always wins. This layer only decides how to read
 it: which lanes are recommended, which are merely suitable, and when even a
 straight-on or a merge deserves the strip. It never invents lane geometry or
 a lane count that the map did not provide.
 */
public enum LaneGuidanceEngine {
    public static func guide(for maneuver: Maneuver, distance: Double, speed: Double,
                             offRoute: Bool, leftTraffic: Bool,
                             next: Maneuver? = nil,
                             nextDistance: Double? = nil) -> LaneGuidance? {
        guard !offRoute, distance.isFinite, distance >= 0 else { return nil }
        var lanes = maneuver.lanes
        if lanes.count < 2, maneuver.type == .roundabout, !maneuver.leavesRoundabout,
           let shape = maneuver.roundabout,
           let rule = shape.ruleLanes(leftTraffic: leftTraffic, hint: maneuver.laneHint) {
            lanes = rule
        }
        guard lanes.count >= 2 else { return nil }

        let kind = kind(for: maneuver)
        let lead = lead(for: kind, speed: speed, laneCount: lanes.count,
                        next: next, nextDistance: nextDistance)
        guard distance <= lead else { return nil }

        let compatible = compatibleIndications(for: maneuver.type, leftTraffic: leftTraffic)
        let guided = lanes.map { lane -> GuidedLane in
            let state: LaneUse
            if lane.valid || lane.indications.contains(where: compatible.contains) {
                state = .recommended
            } else if lane.indications.isEmpty {
                state = .unknown
            } else if isSuitable(lane.indications, for: maneuver.type, leftTraffic: leftTraffic) {
                state = .suitable
            } else {
                state = .unsuitable
            }
            return GuidedLane(indications: lane.indications, use: state)
        }
        // All-unknown is not a recommendation; show the ordinary sign instead of guessing.
        guard guided.contains(where: { $0.use == .recommended || $0.use == .suitable }) else { return nil }

        let good = guided.indices.filter { guided[$0].use == .recommended }
        let detail: String
        if good.isEmpty {
            detail = "Lane recommendation unavailable"
        } else if good.count == guided.count {
            detail = "Any marked lane"
        } else if good.count == 1 {
            detail = "Lane \(good[0] + 1) from left"
        } else {
            detail = "Lanes \(good.map { String($0 + 1) }.joined(separator: ", ")) from left"
        }
        let confidence = guided.allSatisfy { $0.use == .recommended || $0.use == .unsuitable } ? 0.95
            : guided.contains(where: { $0.use == .suitable }) ? 0.75 : 0.5
        return LaneGuidance(lanes: guided, kind: kind, title: title(for: kind),
                            detail: detail,
                            showEarly: next != nil && (nextDistance ?? .infinity) < 500,
                            confidence: confidence)
    }

    public static func kind(for maneuver: Maneuver) -> LaneGuidanceKind {
        switch maneuver.type {
        case .roundabout: return .roundabout
        case .rampLeft, .rampRight: return .motorwayExit
        case .forkLeft, .forkRight, .keepLeft, .keepRight: return .split
        case .merge: return .merge
        case .straight: return .straight
        default: return .turn
        }
    }

    static func lead(for kind: LaneGuidanceKind, speed: Double, laneCount: Int,
                     next: Maneuver?, nextDistance: Double?) -> Double {
        let base = LaneApproach.previewDistance(speed: speed, laneCount: laneCount)
        switch kind {
        case .motorwayExit: return base
        case .turn: return min(base, 520)
        case .roundabout: return min(base, 480)
        case .split, .merge: return min(base, 620)
        case .straight:
            // A straight-on strip only makes sense near a junction or when a close
            // next turn changes the lane; otherwise it is visual noise.
            guard let next, let nextDistance, nextDistance < 450,
                  !isStraight(next.type) else { return 0 }
            return min(360, max(160, speed * 9))
        }
    }

    static func compatibleIndications(for type: ManeuverType, leftTraffic: Bool) -> Set<String> {
        switch type {
        case .turnLeft, .sharpLeft: return ["left", "sharp left"]
        case .turnRight, .sharpRight: return ["right", "sharp right"]
        case .slightLeft, .forkLeft, .keepLeft: return ["slight left", "left", "merge to left"]
        case .slightRight, .forkRight, .keepRight: return ["slight right", "right", "merge to right"]
        case .rampLeft: return leftTraffic ? ["left", "slight left", "merge to left"] : ["left", "slight left"]
        case .rampRight: return leftTraffic ? ["right", "slight right"] : ["right", "slight right", "merge to right"]
        case .merge: return leftTraffic ? ["merge to left", "slight left", "left"] : ["merge to right", "slight right", "right"]
        case .straight: return ["straight"]
        case .uturn: return ["uturn", "reverse"]
        default: return []
        }
    }

    static func isSuitable(_ indications: [String], for type: ManeuverType, leftTraffic: Bool) -> Bool {
        let compatible = compatibleIndications(for: type, leftTraffic: leftTraffic)
        if indications.contains(where: compatible.contains) { return true }
        // A lane that also goes straight is a safe fallback for a gentle fork/merge.
        if [.slightLeft, .slightRight, .forkLeft, .forkRight, .keepLeft, .keepRight, .merge].contains(type),
           indications.contains("straight") { return true }
        return false
    }

    private static func isStraight(_ type: ManeuverType) -> Bool {
        type == .straight || type == .depart
    }

    private static func title(for kind: LaneGuidanceKind) -> String {
        switch kind {
        case .turn: return "Turn lanes"
        case .straight: return "Lanes for the junction"
        case .motorwayExit: return "Exit lanes"
        case .merge: return "Merge lanes"
        case .split: return "Road split"
        case .roundabout: return "Roundabout lanes"
        }
    }
}

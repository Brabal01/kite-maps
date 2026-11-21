import Foundation

public struct JunctionBranch: Equatable, Sendable {
    /// "Keep left", "Exit 8", or the road's own name.
    public var label: String
    public var roadRefs: [String]
    public var isTaken: Bool
    public var laneCount: Int?

    public init(label: String, roadRefs: [String] = [], isTaken: Bool,
                laneCount: Int? = nil) {
        self.label = label
        self.roadRefs = roadRefs
        self.isTaken = isTaken
        self.laneCount = laneCount
    }
}

/**
 A real junction picture, built only from data the router and OSM actually
 supplied. With no exit sign, no lanes and no road reference there is no
 diagram: a made-up fork is worse than the ordinary banner.
 */
public struct JunctionGuide: Equatable, Sendable {
    public var title: String
    public var exitNumber: String?
    public var roadRefs: [String]
    public var destinations: [String]
    public var branches: [JunctionBranch]
    public var takenBranch: Int
    public var recommendedLanes: [Int]
    public var laneCount: Int
    public var distanceMeters: Double
    public var nextInstruction: String?
    public var isMotorway: Bool
    public var confidence: Double

    public init(title: String, exitNumber: String?, roadRefs: [String],
                destinations: [String], branches: [JunctionBranch],
                takenBranch: Int, recommendedLanes: [Int], laneCount: Int,
                distanceMeters: Double, nextInstruction: String?,
                isMotorway: Bool, confidence: Double) {
        self.title = title
        self.exitNumber = exitNumber
        self.roadRefs = roadRefs
        self.destinations = destinations
        self.branches = branches
        self.takenBranch = takenBranch
        self.recommendedLanes = recommendedLanes
        self.laneCount = laneCount
        self.distanceMeters = distanceMeters
        self.nextInstruction = nextInstruction
        self.isMotorway = isMotorway
        self.confidence = confidence
    }
}

public enum JunctionGuideBuilder {
    /// A junction diagram is only for a real motorway/A-road split, not a city turn or a roundabout.
    public static func guide(for maneuver: Maneuver, distance: Double, speed: Double,
                             leftTraffic: Bool, next: Maneuver? = nil,
                             nextDistance: Double? = nil) -> JunctionGuide? {
        guard distance.isFinite, distance >= 0 else { return nil }
        let kind = LaneGuidanceEngine.kind(for: maneuver)
        guard kind == .motorwayExit || kind == .split else { return nil }
        guard distance <= max(650, min(1_300, speed * 26)) else { return nil }
        if maneuver.type == .roundabout { return nil }

        let refs = Array(maneuver.exitSign?.references ?? RoadReferenceParser.find(maneuver.instruction))
        let destinations = maneuver.exitSign?.destinations ?? []
        let lanes = maneuver.lanes
        let sufficient = maneuver.exitSign != nil || lanes.count >= 2 || !refs.isEmpty
        guard sufficient else { return nil }

        let goesLeft = [.rampLeft, .forkLeft, .keepLeft, .slightLeft].contains(maneuver.type)
        let mainLabel: String
        if leftTraffic {
            mainLabel = goesLeft ? "Keep right" : "Keep left"
        } else {
            mainLabel = goesLeft ? "Keep left" : "Keep right"
        }
        let takenLabel: String = maneuver.exitSign?.number.map { "Exit \($0)" }
            ?? (goesLeft ? "Bear left" : "Bear right")
        let taken = JunctionBranch(label: takenLabel, roadRefs: refs,
                                  isTaken: true, laneCount: lanes.count)
        let main = JunctionBranch(label: mainLabel,
                                  roadRefs: Array(RoadReferenceParser.find(maneuver.instruction).prefix(2)),
                                  isTaken: false, laneCount: nil)
        // Keep the visual left-to-right order stable for the diagram.
        let branches = goesLeft ? [taken, main] : [main, taken]
        let takenIndex = goesLeft ? 0 : 1

        var recommended: [Int] = []
        if let laneGuide = LaneGuidanceEngine.guide(for: maneuver, distance: distance,
                                                    speed: speed, offRoute: false,
                                                    leftTraffic: leftTraffic,
                                                    next: next, nextDistance: nextDistance) {
            recommended = laneGuide.recommended
        }
        // A take-it branch with known lanes but no lane recommendation would look
        // contradictory; only report the lanes we can actually justify.
        let confidence: Double
        switch (maneuver.exitSign != nil, !refs.isEmpty, lanes.count >= 2) {
        case (true, _, true): confidence = 0.98
        case (true, _, false): confidence = 0.82
        case (false, true, true): confidence = 0.8
        case (false, true, false): confidence = 0.6
        default: confidence = 0.5
        }

        let motorway = maneuver.exitSign != nil ||
            refs.contains { $0.hasPrefix("M") || $0.hasPrefix("A") } ||
            maneuver.instruction.localizedCaseInsensitiveContains("motorway") ||
            maneuver.instruction.localizedCaseInsensitiveContains("exit")
        let title = kind == .motorwayExit ? "Motorway exit" : "Road split"
        return JunctionGuide(title: title,
                             exitNumber: maneuver.exitSign?.number,
                             roadRefs: refs, destinations: destinations,
                             branches: branches, takenBranch: takenIndex,
                             recommendedLanes: recommended, laneCount: lanes.count,
                             distanceMeters: distance,
                             nextInstruction: next.map { SpokenText.forScreen($0.instruction) },
                             isMotorway: motorway, confidence: confidence)
    }

    public static func shouldShow(_ guide: JunctionGuide?) -> Bool {
        guide != nil && (guide?.confidence ?? 0) >= 0.5
    }
}

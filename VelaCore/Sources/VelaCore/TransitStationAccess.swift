import Foundation

public struct TransitCall: Hashable, Sendable {
    public let name: String
    public let timeZone: String?
    public let arrival: Date?
    public let departure: Date?
    public let track: String?
    public let scheduledTrack: String?
    public let stopCode: String?
    public let detail: String?
    public var skipped: Bool
    /** The feed's own stop id, when it provides one, for joining GTFS-Realtime updates. */
    public var stopId: String? = nil
    public var location: LatLng? = nil
}

public struct TransitWalkStep: Hashable, Sendable {
    public let direction: String
    public let street: String?
    public let distance: Double
    public let fromLevel: Double?
    public let toLevel: Double?
    let fromNode: Int64?
    let toNode: Int64?
}

/** Match named subway portals to the actual pedestrian path using MOTIS's OSM node IDs. */
public enum TransitStationAccess {
    public struct Portal: Hashable, Sendable {
        public let reference: String?
        public let name: String?
        public let destination: String?
    }

    public struct Passage: Hashable, Sendable {
        public var exit: Portal?
        public var entrance: Portal?
    }

    struct Segment {
        let index: Int
        var exitNodes: [Int64]
        var entranceNodes: [Int64]
    }

    public static func resolve(_ trip: TransitTrip) async -> [Int: Passage] {
        let segments = segments(in: trip)
        let nodeIDs = Set(segments.flatMap { $0.exitNodes + $0.entranceNodes }).sorted()
        guard !nodeIDs.isEmpty else { return [:] }
        let ids = nodeIDs.map(String.init).joined(separator: ",")
        // The IDs must be interpolated. The previous literal "(ids)" asked
        // Overpass for a node called "ids", so entrance enrichment silently
        // found nothing on every journey.
        let query = entranceQuery(ids)
        guard let data = await Overpass.firstAnswer(query, stagger: 3, valid: { elements($0) != nil }),
              !Task.isCancelled else { return [:] }
        return match(segments, data: data)
    }

    /// The Overpass query for the entrances of the given OSM node ids.
    static func entranceQuery(_ ids: String) -> String {
        """
        [out:json][timeout:8];node(id:(\(ids)))["railway"="subway_entrance"];out tags;
        """
    }

    static func segments(in trip: TransitTrip) -> [Segment] {
        let legs = trip.legs
        return legs.indices.compactMap { index in
            let walk = legs[index]
            guard walk.isWalk, !walk.walkSteps.isEmpty else { return nil }
            let afterMetro = index > 0 && legs[index - 1].vehicle == .metro
            let beforeMetro = index + 1 < legs.count && legs[index + 1].vehicle == .metro
            guard afterMetro || beforeMetro else { return nil }
            // Bound each end geographically along the traced walk. A different station farther
            // down the street must never become the exit from the one we just got off at.
            func nearbyNodes(_ steps: [TransitWalkStep], reversed: Bool) -> [Int64] {
                var nodes: [Int64] = []
                var distance = 0.0
                for step in steps.prefix(30) {
                    let pair = reversed ? [step.toNode, step.fromNode] : [step.fromNode, step.toNode]
                    if let start = pair[0], start > 0, nodes.last != start { nodes.append(start) }
                    distance += max(0, step.distance)
                    guard distance <= 350 else { break }
                    if let end = pair[1], end > 0, nodes.last != end { nodes.append(end) }
                }
                return nodes
            }
            let exitNodes = afterMetro ? nearbyNodes(walk.walkSteps, reversed: false) : []
            let entranceNodes = beforeMetro ? nearbyNodes(Array(walk.walkSteps.reversed()), reversed: true) : []
            guard !exitNodes.isEmpty || !entranceNodes.isEmpty else { return nil }
            return Segment(index: index, exitNodes: exitNodes, entranceNodes: entranceNodes)
        }
    }

    static func match(_ segments: [Segment], data: Data) -> [Int: Passage] {
        var portals: [Int64: Portal] = [:]
        for item in elements(data) ?? [] {
            guard let id = item["id"] as? Int64, let tags = item["tags"] as? [String: String],
                  tags["railway"] == "subway_entrance", tags["access"] != "no", tags["access"] != "private" else { continue }
            func clean(_ key: String) -> String? {
                let value = tags[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
                return value?.isEmpty == false ? value : nil
            }
            let portal = Portal(reference: clean("ref"), name: clean("name"), destination: clean("destination") ?? clean("exit_to"))
            if portal.reference != nil || portal.name != nil || portal.destination != nil { portals[id] = portal }
        }
        var result: [Int: Passage] = [:]
        for segment in segments {
            let exit = segment.exitNodes.lazy.compactMap { portals[$0] }.first
            let entrance = segment.entranceNodes.lazy.compactMap { portals[$0] }.first
            if exit != nil || entrance != nil { result[segment.index] = Passage(exit: exit, entrance: entrance) }
        }
        return result
    }

    private static func elements(_ data: Data) -> [[String: Any]]? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["elements"] as? [[String: Any]]
    }
}

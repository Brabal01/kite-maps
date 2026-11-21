import Foundation

/**
 * Decides which traffic lights, stop signs and crossings actually belong to the road the driver is
 * on, in the direction they are travelling.
 *
 * Proximity alone is not enough. On a big junction a light for the opposite carriageway, or for the
 * road crossing ours, can sit within a few metres of the blue line. The matcher therefore asks
 * whether the route follows the OSM way the control is mapped on, in the direction that way may be
 * travelled, and whether the control is tagged as facing that direction. Only then is a light
 * presented as the driver's own.
 */
public enum DirectionalRoadControlMatcher {
    public struct Way {
        var id: Int64
        var nodes: [Int64]
        var points: [LatLng]
        var tags: [String: String]
        var isRail: Bool { tags["railway"] != nil }
        var isRoad: Bool { tags["highway"] != nil }
        var layer: Int { Int(tags["layer"] ?? "0") ?? 0 }
    }

    /// How sure the matcher is that the control faces the driver.
    public typealias Relevance = RouteControl.Relevance

    struct Candidate {
        var control: RouteControl
        var along: Double
        var offset: Double
        var wayID: Int64?
        var nodeID: Int64
        var relevance: Relevance
    }

    public static func match(elements: [[String: Any]], on line: [LatLng], cumulative: [Double]) -> [RouteControl] {
        guard line.count >= 2, !elements.isEmpty else { return [] }
        let total = cumulative.last ?? 0
        // Way metadata is needed even when Overpass returns no geometry (a Postpass answer, or a
        // node shared with a railway): a tram crossing is still a tram crossing without its shape.
        var roadNodes = Set<Int64>()
        var railKinds: [Int64: RouteControl.Kind] = [:]
        for e in elements where e["type"] as? String == "way" {
            guard let nodes = (e["nodes"] as? [NSNumber])?.map(\.int64Value) else { continue }
            let tags = e["tags"] as? [String: String] ?? [:]
            if tags["highway"] != nil { roadNodes.formUnion(nodes) }
            switch tags["railway"] {
            case "tram", "light_rail":
                for n in nodes { railKinds[n] = .tram }
            case "rail", "narrow_gauge":
                for n in nodes where railKinds[n] == nil { railKinds[n] = .railway }
            default: break
            }
        }
        let ways = parseWays(elements)
        var nodeIndex: [Int64: [(way: Int, index: Int)]] = [:]
        for (wi, w) in ways.enumerated() {
            for (i, n) in w.nodes.enumerated() { nodeIndex[n, default: []].append((wi, i)) }
        }

        func bearing(_ along: Double) -> Double? {
            let a = Geo.point(along: line, meters: max(0, along - 12), cumulative: cumulative)
            let b = Geo.point(along: line, meters: min(total, along + 12), cumulative: cumulative)
            return a.distance(to: b) > 3 ? Geo.bearing(a, b) : nil
        }

        /// A point [meters] along [w] from [index] in [dir] (1 along its order, -1 against).
        func along(_ w: Way, _ index: Int, _ dir: Int, meters: Double) -> LatLng? {
            var travelled = 0.0
            var previous = w.points[index]
            var j = index + dir
            while j >= 0, j < w.points.count {
                let next = w.points[j]
                let d = previous.distance(to: next)
                if travelled + d >= meters {
                    let f = d > 0 ? (meters - travelled) / d : 0
                    return LatLng(previous.lat + (next.lat - previous.lat) * f,
                                  previous.lng + (next.lng - previous.lng) * f)
                }
                travelled += d
                previous = next
                j += dir
            }
            return travelled > 6 ? previous : nil
        }

        func wayBearing(_ w: Way, _ index: Int, _ dir: Int) -> Double? {
            guard let p = along(w, index, dir, meters: 20) else { return nil }
            return w.points[index].distance(to: p) > 3 ? Geo.bearing(w.points[index], p) : nil
        }

        /// Whether the route is really travelling along [w] in [dir] at this node.
        func routeFollows(_ w: Way, _ index: Int, _ dir: Int, at nodeAlong: Double) -> Bool {
            guard let sample = along(w, index, dir, meters: 20) else { return false }
            let p = Geo.project(sample, on: line, cumulative: cumulative)
            guard p.offset <= 4.5, p.along > nodeAlong + 4, p.along < nodeAlong + 55 else { return false }
            guard let rb = bearing(p.along), let wb = wayBearing(w, index, dir) else { return false }
            return Roundabouts.angleGap(rb, wb) < 42
        }

        func legal(_ w: Way, _ dir: Int, directionTag: String?) -> Bool {
            let oneway = Roundabouts.onewayDirection(w.tags)
            guard oneway == 0 || oneway == dir else { return false }
            if let directionTag {
                if directionTag == "forward", dir != 1 { return false }
                if directionTag == "backward", dir != -1 { return false }
            }
            let access = w.tags["access"] ?? w.tags["motor_vehicle"]
            if ["no", "private"].contains(access) { return false }
            return true
        }

        var candidates: [Candidate] = []
        for item in elements where item["type"] as? String == "node" {
            guard let id = (item["id"] as? NSNumber)?.int64Value,
                  let lat = item["lat"] as? Double, let lon = item["lon"] as? Double else { continue }
            let point = LatLng(lat, lon)
            let tags = item["tags"] as? [String: String] ?? [:]
            let explicit = RouteControls.kind(for: tags)
            let inferred = roadNodes.contains(id) ? railKinds[id] : nil
            guard let kind = explicit == .railway ? (railKinds[id] ?? explicit) : (explicit ?? inferred) else { continue }
            let at = Geo.project(point, on: line, cumulative: cumulative)
            let crossing = kind == .railway || kind == .tram || kind == .crossing
            let reach: Double = crossing ? 15 : (kind == .light ? 12 : 10)
            guard at.offset <= reach, at.along > 0, at.along < total else { continue }
            let directionTag = tags["traffic_signals:direction"] ?? tags["direction"]
            let refs = nodeIndex[id] ?? []
            let relevantWays = refs.compactMap { ref -> (Way, Int)? in
                let w = ways[ref.way]
                // A control is about the road it sits on; a bridge or tunnel overhead is not ours.
                if crossing, w.isRail, w.layer != 0 { return nil }
                if !w.isRoad, !w.isRail { return nil }
                return (w, ref.index)
            }
            var relevant = false
            var ambiguous = false
            var wayID: Int64?
            var confidence = 0.55
            if relevantWays.isEmpty {
                // No way geometry (Postpass answers often carry only the point). Keep a control
                // that sits on the line itself; anything further off could be any approach.
                if at.offset <= 4 {
                    if directionTag == nil || directionTag == "forward" {
                        relevant = true
                        confidence = 0.55
                    } else if directionTag == "backward" {
                        // Faces the other way: not ours while driving.
                        continue
                    } else {
                        ambiguous = true
                        confidence = 0.3
                    }
                } else {
                    ambiguous = true
                }
            } else {
                for (w, index) in relevantWays {
                    for dir in [1, -1] {
                        guard legal(w, dir, directionTag: directionTag) else { continue }
                        if routeFollows(w, index, dir, at: at.along) {
                            relevant = true
                            wayID = w.id
                            confidence = directionTag == nil ? 0.9 : 0.96
                            break
                        }
                    }
                    if relevant { break }
                }
                if !relevant {
                    // A head explicitly tagged as facing the other way, on the very way we
                    // travel, is not ambiguous: it is the opposite direction's light.
                    if let tag = directionTag, tag == "forward" || tag == "backward" {
                        let opposite = tag == "forward" ? -1 : 1
                        if relevantWays.contains(where: { routeFollows($0.0, $0.1, opposite, at: at.along) }) {
                            continue
                        }
                    }
                    // On a way that meets ours at a junction, but not on the road we travel:
                    // it may be the far side of our junction, or another arm's. Never certain.
                    ambiguous = refs.contains { ways[$0.way].isRoad }
                    confidence = 0.35
                }
            }
            if !relevant, !ambiguous { continue }
            if !relevant, directionTag != nil, directionTag != "forward", directionTag != "backward" {
                // An explicit compass direction we cannot interpret: leave it to browsing only.
                confidence = 0.3
            }
            let relevance: Relevance = relevant ? .relevant : .ambiguous
            let control = RouteControl(kind: kind, location: point, osmID: id, wayID: wayID,
                                       directionTag: directionTag, alongMeters: at.along,
                                       offsetMeters: at.offset, confidence: confidence,
                                       source: "osm", directionCertain: relevant,
                                       relevance: relevance,
                                       stopLineKey: "\(wayID.map(String.init) ?? wKey(refs))|\(id)")
            candidates.append(Candidate(control: control, along: at.along, offset: at.offset,
                                        wayID: wayID, nodeID: id, relevance: relevance))
        }
        return dedupe(candidates)
    }

    /// A fallback identity for a control whose way wasn't returned.
    private static func wKey(_ refs: [(way: Int, index: Int)]) -> String {
        refs.isEmpty ? "unknown" : refs.map { "\($0.way)" }.sorted().joined(separator: "+")
    }

    /**
     * One marker per stop line, not one per distance. Two heads on the same way a few metres apart
     * are one junction; two separate junctions 20 m apart on the same road are two.
     */
    static func dedupe(_ candidates: [Candidate]) -> [RouteControl] {
        var sorted = candidates.sorted { $0.along < $1.along }
        var out: [Candidate] = []
        for candidate in sorted {
            if let i = out.indices.last(where: { out[$0].control.kind == candidate.control.kind
                && candidate.along - out[$0].along < 12
                && (out[$0].wayID == candidate.wayID || (out[$0].offset < 6 && candidate.offset < 6
                    && abs(candidate.along - out[$0].along) < 8)) }) {
                // Keep the better-evidenced, closer-to-the-line head, but never turn an ambiguous
                // one into a certain one just because a certain neighbour exists.
                let better = candidate.control.confidence > out[i].control.confidence
                    || (candidate.control.confidence == out[i].control.confidence && candidate.offset < out[i].offset)
                if better { out[i] = candidate }
                continue
            }
            out.append(candidate)
        }
        sorted = out
        return sorted.map(\.control)
    }

    static func parseWays(_ elements: [[String: Any]]) -> [Way] {
        var seen = Set<Int64>()
        var out: [Way] = []
        for e in elements where e["type"] as? String == "way" {
            guard let id = (e["id"] as? NSNumber)?.int64Value, seen.insert(id).inserted,
                  let nodes = (e["nodes"] as? [NSNumber])?.map(\.int64Value),
                  let geometry = e["geometry"] as? [[String: Any]], geometry.count == nodes.count, nodes.count >= 2 else { continue }
            let points = geometry.compactMap { g -> LatLng? in
                guard let lat = g["lat"] as? Double, let lon = g["lon"] as? Double else { return nil }
                return LatLng(lat, lon)
            }
            guard points.count == nodes.count else { continue }
            out.append(Way(id: id, nodes: nodes, points: points, tags: e["tags"] as? [String: String] ?? [:]))
        }
        return out
    }
}

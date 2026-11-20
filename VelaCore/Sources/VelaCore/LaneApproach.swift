import Foundation

public enum LaneApproach {
    /// Show the marked lane assignment earlier at highway speed and on wider approaches.
    public static func previewDistance(speed: Double, laneCount: Int) -> Double {
        let seconds = laneCount >= 4 ? 24.0 : 19.0
        return min(900, max(300, max(0, speed) * seconds))
    }

    public static func showsStrip(distance: Double, speed: Double, laneCount: Int, offRoute: Bool) -> Bool {
        let seconds = laneCount >= 4 ? 12.5 : 11.0
        let lead = min(450, max(110, speed * seconds))
        return !offRoute && (0...lead).contains(distance)
    }
}

extension LaneApproach {
    public static func mappedLanes(for maneuver: Maneuver, on line: [LatLng]) async -> [Lane] {
        guard line.count >= 2, maneuver.alongMeters > 15 else { return [] }
        let distance = Geo.cumulative(line)
        let point = Geo.point(along: line, meters: maneuver.alongMeters - 14, cumulative: distance)
        let earlier = Geo.point(along: line, meters: maneuver.alongMeters - 35, cumulative: distance)
        let coordinate = String(format: "%.6f,%.6f", locale: Locale(identifier: "en_US_POSIX"), point.lat, point.lng)
        let query = "[out:json][timeout:10];way[\"highway\"](around:24,\(coordinate));out tags geom 35;"
        let bearing = Geo.bearing(earlier, point)
        guard earlier.distance(to: point) > 8,
              let data = await Overpass.firstAnswer(query, stagger: 3, valid: { elements($0) != nil }) else { return [] }
        let candidates = (elements(data) ?? []).compactMap { way -> (Double, [Lane])? in
            guard let tags = way["tags"] as? [String: String],
                  let shape = way["geometry"] as? [[String: Double]] else { return nil }
            let geometry = shape.compactMap { item -> LatLng? in
                guard let lat = item["lat"], let lng = item["lon"] else { return nil }
                return LatLng(lat, lng)
            }
            guard geometry.count >= 2 else { return nil }
            let distances = Geo.cumulative(geometry)
            let match = Geo.project(point, on: geometry, cumulative: distances)
            guard match.offset <= 13 else { return nil }
            let a = Geo.point(along: geometry, meters: match.along - 9, cumulative: distances)
            let b = Geo.point(along: geometry, meters: match.along + 9, cumulative: distances)
            guard a.distance(to: b) > 5 else { return nil }
            let delta = abs(Geo.bearing(a, b) - bearing)
            let turn = min(delta, 360 - delta)
            guard turn < 38 || turn > 142 else { return nil }
            let forward = turn < 90
            let oneWay = tags["oneway"]
            if oneWay == "-1" && forward { return nil }
            let forwardOnly = ["yes", "1", "true"].contains(oneWay ?? "") || (tags["highway"] == "motorway" && oneWay == nil)
            if forwardOnly && !forward { return nil }
            let suffix = forward ? ":forward" : ":backward"
            let both = oneWay == "-1" || forwardOnly
            let raw = tags["turn:lanes"+suffix] ?? (both ? tags["turn:lanes"] : nil)
            let count = (tags["lanes"+suffix] ?? (both ? tags["lanes"] : nil)).flatMap(Int.init)
            let lanes = laneList(turns: raw, count: count, maneuver: maneuver)
            // Compare even untagged parallel roads, so we don't borrow the other carriageway's lanes.
            return (match.offset + min(turn, 180-turn) / 12, lanes)
        }.sorted { $0.0 < $1.0 }
        guard let best = candidates.first, !best.1.isEmpty,
              !candidates.dropFirst().contains(where: { $0.0 - best.0 < 3 && $0.1 != best.1 }) else { return [] }
        return best.1
    }

    static func laneList(turns: String?, count: Int?, maneuver: Maneuver) -> [Lane] {
        let indications = turns?.split(separator: "|", omittingEmptySubsequences: false).map { part in
            part.split(separator: ";").map { String($0).replacingOccurrences(of: "_", with: " ") }
                .map { $0 == "through" ? "straight" : $0 == "reverse" ? "uturn" : $0 }
        } ?? []
        let size = count ?? indications.count
        guard (2...12).contains(size) else { return [] }
        let arrows = indications.count == size ? indications : Array(repeating: [], count: size)
        let compatible: Set<String>
        switch maneuver.type {
        case .rampLeft, .forkLeft, .keepLeft, .slightLeft: compatible = ["slight left", "merge to left", "left"]
        case .rampRight, .forkRight, .keepRight, .slightRight: compatible = ["slight right", "merge to right", "right"]
        case .turnLeft, .sharpLeft: compatible = ["left", "sharp left"]
        case .turnRight, .sharpRight: compatible = ["right", "sharp right"]
        case .straight: compatible = ["straight"]
        case .uturn: compatible = ["uturn"]
        default: compatible = []
        }
        var lanes = arrows.map { Lane(indications: $0, valid: $0.contains(where: compatible.contains)) }
        if !lanes.contains(where: \.valid) {
            let hint = maneuver.laneHint?.lowercased().trimmingCharacters(in: .punctuationCharacters) ?? ""
            if hint == "use the left lane" { lanes[0].valid = true }
            if hint == "use the right lane" { lanes[size - 1].valid = true }
        }
        return lanes
    }

    private static func elements(_ data: Data) -> [[String: Any]]? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["elements"] as? [[String: Any]]
    }
}

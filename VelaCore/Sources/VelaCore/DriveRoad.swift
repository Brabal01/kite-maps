import Foundation

public enum DriveRoad {
    public struct Match: Sendable {
        public let name: String?
        public let limit: Double?
    }

    public static func lookup(_ location: LatLng, course: Double) async -> Match? {
        let coordinate = String(format: "%.6f,%.6f", locale: Locale(identifier: "en_US_POSIX"), location.lat, location.lng)
        let roads = "motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service|.*_link"
        let query = "[out:json][timeout:12];way[\"highway\"~\"^(\(roads))$\"](around:35,\(coordinate));out tags geom 25;"
        guard let data = await Overpass.firstAnswer(query, stagger: 4, valid: { elements($0) != nil }),
              let elements = elements(data) else { return nil }
        let candidates = elements.compactMap { way -> (Double, Match)? in
            guard let tags = way["tags"] as? [String: String], let geometry = way["geometry"] as? [[String: Double]] else { return nil }
            let line = geometry.compactMap { item -> LatLng? in
                guard let lat = item["lat"], let lng = item["lon"] else { return nil }
                return LatLng(lat, lng)
            }
            guard line.count >= 2 else { return nil }
            let cumulative = Geo.cumulative(line)
            let match = Geo.project(location, on: line, cumulative: cumulative)
            guard match.offset <= 18 else { return nil }
            let before = Geo.point(along: line, meters: match.along - 8, cumulative: cumulative)
            let after = Geo.point(along: line, meters: match.along + 8, cumulative: cumulative)
            let bearing = Geo.bearing(before, after)
            let difference = abs(course - bearing).truncatingRemainder(dividingBy: 360)
            let forwardAngle = min(difference, 360 - difference)
            if course >= 0 {
                if tags["oneway"] == "yes" && forwardAngle > 55 { return nil }
                if tags["oneway"] == "-1" && forwardAngle < 125 { return nil }
                if (55...125).contains(forwardAngle) { return nil }
            }
            let directional = course >= 0 ? tags[forwardAngle < 90 ? "maxspeed:forward" : "maxspeed:backward"] : nil
            let limit = (directional ?? tags["maxspeed"]).flatMap(Overpass.maxspeedKmh)
            return (match.offset, Match(name: tags["name"] ?? tags["ref"], limit: limit))
        }.sorted { $0.0 < $1.0 }
        guard let first = candidates.first else { return nil }
        if candidates.dropFirst().contains(where: { $0.0 - first.0 < 4 && ($0.1.name != first.1.name || $0.1.limit != first.1.limit) }) {
            return Match(name: nil, limit: nil)
        }
        return first.1
    }

    private static func elements(_ data: Data) -> [[String: Any]]? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["elements"] as? [[String: Any]]
    }
}

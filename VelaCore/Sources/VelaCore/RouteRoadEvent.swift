import Foundation

public struct RouteRoadEvent: Identifiable, Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case trafficLight, stop, railway, pedestrian

        public var title: String {
            switch self {
            case .trafficLight: return "Traffic lights"
            case .stop: return "Stop signs"
            case .railway: return "Level crossings"
            case .pedestrian: return "Pedestrian crossings"
            }
        }

        public var icon: String {
            switch self {
            case .trafficLight: return "traffic.light"
            case .stop: return "octagon.fill"
            case .railway: return "tram.fill"
            case .pedestrian: return "figure.walk"
            }
        }
    }

    public var id: Int64
    public var kind: Kind
    public var point: LatLng
    public var along: Double

    public static func load(on line: [LatLng], from: Double, length: Double) async -> [Self] {
        let cumulative = Geo.cumulative(line)
        let slice = Geo.slice(line, from: from, to: from + length, cumulative: cumulative)
        guard slice.count >= 2 else { return [] }
        let segmentLength = Geo.length(slice)
        let count = max(1, Int((segmentLength / 28).rounded(.up)))
        let distances = Geo.cumulative(slice)
        let points = (0...count).map { Geo.point(along: slice, meters: segmentLength * Double($0) / Double(count), cumulative: distances) }
        let coords = points.map { String(format: "%.5f,%.5f", $0.lat, $0.lng) }.joined(separator: ",")
        let constraint = "(around:12,\(coords))"
        let query = "[out:json][timeout:10];(node[highway~\"^(traffic_signals|stop|crossing)$\"]\(constraint);"
            + "node[railway~\"^(level_crossing|crossing)$\"]\(constraint););out body;"
        guard let data = await Overpass.firstAnswer(query, stagger: 2.5, valid: { (try? JSONSerialization.jsonObject(with: $0)) != nil }) else { return [] }
        return matched(data, line: slice, traveled: from)
    }

    static func matched(_ data: Data, line: [LatLng], traveled: Double) -> [Self] {
        guard line.count >= 2, let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nodes = response["elements"] as? [[String: Any]] else { return [] }
        let cumulative = Geo.cumulative(line)
        let events: [Self] = nodes.compactMap { node in
            guard let id = (node["id"] as? NSNumber)?.int64Value, let lat = node["lat"] as? Double,
                  let lon = node["lon"] as? Double, let tags = node["tags"] as? [String: String] else { return nil }
            let kind: Kind
            if ["level_crossing", "crossing"].contains(tags["railway"] ?? "") { kind = .railway }
            else {
                switch tags["highway"] {
                case "traffic_signals": kind = .trafficLight
                case "stop": kind = .stop
                case "crossing": kind = .pedestrian
                default: return nil
                }
            }
            let position = LatLng(lat, lon)
            let match = Geo.project(position, on: line, cumulative: cumulative)
            guard match.offset <= (kind == .stop ? 5 : 8) else { return nil }
            if let raw = tags["direction"], let bearing = Double(raw) {
                let before = Geo.point(along: line, meters: max(0, match.along - 10), cumulative: cumulative)
                let after = Geo.point(along: line, meters: match.along + 10, cumulative: cumulative)
                let angle = abs(Geo.bearing(before, after) - bearing).truncatingRemainder(dividingBy: 360)
                guard min(angle, 360 - angle) < 70 else { return nil }
            }
            return Self(id: id, kind: kind, point: position, along: match.along + traveled)
        }
        var previous: [Kind: Double] = [:]
        return events.sorted { $0.along < $1.along }.filter { event in
            if let last = previous[event.kind], event.along - last < 18 { return false }
            previous[event.kind] = event.along
            return true
        }
    }
}

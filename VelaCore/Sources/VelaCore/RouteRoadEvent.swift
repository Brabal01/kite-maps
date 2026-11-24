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

    public static func load(on line: [LatLng], from: Double, length: Double) async -> [Self]? {
        let cumulative = Geo.cumulative(line)
        let slice = Geo.slice(line, from: from, to: from + length, cumulative: cumulative)
        guard slice.count >= 2 else { return [] }
        let segmentLength = Geo.length(slice)
        let count = min(150, max(1, Int((segmentLength / 28).rounded(.up))))
        let distances = Geo.cumulative(slice)
        let points = (0...count).map {
            Geo.point(along: slice, meters: segmentLength * Double($0) / Double(count), cumulative: distances)
        }
        let coords = points.map { String(format: "%.5f,%.5f", $0.lat, $0.lng) }.joined(separator: ",")
        let query = """
        [out:json][timeout:8];
        (node[highway="traffic_signals"](around:42,\(coords));
         node[highway~"^(stop|crossing)$"](around:28,\(coords));
         node[railway~"^(level_crossing|crossing)$"](around:28,\(coords));)->.controls;
        .controls out body 900;
        """
        let valid: @Sendable (Data) -> Bool = {
            guard let response = try? JSONSerialization.jsonObject(with: $0) as? [String: Any] else { return false }
            return response["remark"] == nil && response["elements"] is [[String: Any]]
        }
        let ways = "way(bn.controls)[highway];out geom 180;"
        if let data = await Overpass.firstAnswer(query + ways, stagger: 1.5, valid: valid) {
            return matched(data, line: slice, traveled: from)
        }
        guard !Task.isCancelled, let data = await Overpass.firstAnswer(query, stagger: 1.5, valid: valid) else { return nil }
        return matched(data, line: slice, traveled: from)
    }

    static func matched(_ data: Data, line: [LatLng], traveled: Double) -> [Self] {
        guard line.count >= 2, let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nodes = response["elements"] as? [[String: Any]] else { return [] }
        let cumulative = Geo.cumulative(line)
        var waysByNode: [Int64: [[LatLng]]] = [:]
        for way in nodes where way["type"] as? String == "way" {
            let geometry = (way["geometry"] as? [[String: Any]] ?? []).compactMap { point -> LatLng? in
                guard let lat = point["lat"] as? Double, let lon = point["lon"] as? Double else { return nil }
                return LatLng(lat, lon)
            }
            guard geometry.count >= 2 else { continue }
            for id in way["nodes"] as? [NSNumber] ?? [] {
                waysByNode[id.int64Value, default: []].append(geometry)
            }
        }
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
            let roadsideWays = waysByNode[id] ?? []
            let radius = kind == .trafficLight || kind == .stop ? 4.0 : 5.0
            if match.offset > radius {
                guard match.offset <= 12, roadsideWays.contains(where: { way in
                    sharesApproach(position, way: way, line: line, cumulative: cumulative)
                }) else { return nil }
            }
            let heading = bearing(on: line, at: match.along, cumulative: cumulative)
            let direction = tags["traffic_signals:direction"] ?? tags["direction"]
            if let bearings = RoadCamera.bearings(direction) {
                guard bearings.contains(where: { abs(NavigationCamera.shortestTurn(from: heading, to: $0)) <= 65 }) else { return nil }
            } else if direction == "forward" || direction == "backward", !roadsideWays.isEmpty {
                guard roadsideWays.contains(where: { way in
                    let distances = Geo.cumulative(way)
                    let at = Geo.project(position, on: way, cumulative: distances).along
                    let forward = bearing(on: way, at: at, cumulative: distances)
                    let expected = direction == "forward" ? forward : (forward + 180).truncatingRemainder(dividingBy: 360)
                    return abs(NavigationCamera.shortestTurn(from: heading, to: expected)) <= 65
                }) else { return nil }
            }
            let onRoute = Geo.point(along: line, meters: match.along, cumulative: cumulative)
            return Self(id: id, kind: kind, point: onRoute, along: match.along + traveled)
        }
        var previous: [Kind: Double] = [:]
        return events.sorted { $0.along < $1.along }.filter { event in
            if let last = previous[event.kind], event.along - last < 35 { return false }
            previous[event.kind] = event.along
            return true
        }
    }

    private static func bearing(on line: [LatLng], at meters: Double, cumulative: [Double]) -> Double {
        let before = Geo.point(along: line, meters: meters - 5, cumulative: cumulative)
        let after = Geo.point(along: line, meters: meters + 5, cumulative: cumulative)
        return Geo.bearing(before, after)
    }

    private static func sharesApproach(_ position: LatLng, way: [LatLng], line: [LatLng], cumulative: [Double]) -> Bool {
        let distances = Geo.cumulative(way)
        let onWay = Geo.project(position, on: way, cumulative: distances).along
        let length = distances.last ?? 0
        return [-1.0, 1.0].contains { side in
            let start = onWay + 10 * side
            let stop = onWay + 20 * side
            guard (0...length).contains(start), (0...length).contains(stop) else { return false }
            let a = Geo.point(along: way, meters: start, cumulative: distances)
            let b = Geo.point(along: way, meters: stop, cumulative: distances)
            let first = Geo.project(a, on: line, cumulative: cumulative)
            let second = Geo.project(b, on: line, cumulative: cumulative)
            return first.offset <= 7.5 && second.offset <= 7.5 && abs(first.along - second.along) > 5
        }
    }

}

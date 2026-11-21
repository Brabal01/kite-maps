import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct RouteControl: Hashable, Sendable {
    /// Whether the control is known to face the direction the driver travels.
    public enum Relevance: String, Hashable, Sendable {
        case relevant, ambiguous, irrelevant
    }

    public enum Kind: String, Hashable, Sendable {
        case light = "traffic-light", stop = "route-stop", railway = "route-crossing", tram = "tram-crossing", crossing = "pedestrian-crossing", yield = "give-way", oneWay = "one-way"

        public var showsDuringDriving: Bool {
            switch self {
            case .light, .stop, .railway: return true
            case .tram, .crossing, .yield, .oneWay: return false
            }
        }
    }

    public let kind: Kind
    /// The mapped position. Kept, so a signal is never silently moved to the middle of a junction.
    public let location: LatLng
    /// The original OSM node id, for diagnostics and de-duplication.
    public var osmID: Int64?
    /// The OSM way whose approach this control governs, when known.
    public var wayID: Int64?
    /// `traffic_signals:direction` / `direction` as tagged.
    public var directionTag: String?
    /// Distance from the start of the route, when it was matched to a route.
    public var alongMeters: Double?
    /// How far the mapped point sits from the route line.
    public var offsetMeters: Double?
    /// 0…1 confidence that this control belongs to our approach.
    public var confidence: Double
    public var source: String
    /// True only when the way topology and direction say this is our approach.
    public var directionCertain: Bool
    public var relevance: Relevance
    /// The identity of one physical stop line, for de-duplication.
    public var stopLineKey: String?

    public init(kind: Kind, location: LatLng, osmID: Int64? = nil, wayID: Int64? = nil,
                directionTag: String? = nil, alongMeters: Double? = nil, offsetMeters: Double? = nil,
                confidence: Double = 0.6, source: String = "osm", directionCertain: Bool = true,
                relevance: Relevance = .relevant, stopLineKey: String? = nil) {
        self.kind = kind
        self.location = location
        self.osmID = osmID
        self.wayID = wayID
        self.directionTag = directionTag
        self.alongMeters = alongMeters
        self.offsetMeters = offsetMeters
        self.confidence = confidence
        self.source = source
        self.directionCertain = directionCertain
        self.relevance = relevance
        self.stopLineKey = stopLineKey
    }
}

public enum RouteControls {
    /**
     * Controls around a point. With a confirmed GPS heading, a short synthetic line
     * along that heading lets the directional matcher reject the opposite
     * carriageway and the crossing road; without one, the old proximity list is
     * kept as browsing context.
     */
    public static func nearby(_ point: LatLng, heading: Double? = nil) async -> [RouteControl]? {
        let lat = point.lat, lon = point.lng
        async let overpass = fetchControls(around: "550,\(lat),\(lon)")
        async let postpass = fetchPostpass(covering: [point], padding: 550)
        guard let items = await combined(overpass, postpass) else { return nil }
        guard let heading, heading.isFinite, (0..<360).contains(heading) else { return nodeControls(items) }
        func offset(_ bearing: Double, _ meters: Double) -> LatLng {
            let a = bearing * .pi / 180
            return LatLng(point.lat + meters * cos(a) / 110_540,
                          point.lng + meters * sin(a) / (111_320 * max(0.01, cos(point.lat * .pi / 180))))
        }
        let line = [offset(heading + 180, 30), point, offset(heading, 220)]
        return DirectionalRoadControlMatcher.match(elements: items, on: line, cumulative: Geo.cumulative(line))
    }

    private static func fetchControls(around scope: String, walking: Bool = false) async -> [[String: Any]]? {
        let minimal = """
        [out:json][timeout:6];
        (node["highway"~"^(traffic_signals|stop|crossing|give_way)$"](around:\(scope));
         node["railway"~"^(level_crossing|crossing|tram_level_crossing)$"](around:\(scope)););
        out body 400;
        """
        async let tagged = Overpass.firstAnswer(minimal, stagger: 0.75, requestTimeout: 7, valid: { elements($0) != nil })
        async let detailed = Overpass.firstAnswer(query(around: scope, walking: walking), stagger: 0.75, requestTimeout: 8, valid: { elements($0) != nil })
        let (taggedData, detailedData) = await (tagged, detailed)
        let explicit = taggedData.flatMap(elements)
        let enriched = detailedData.flatMap(elements)
        guard explicit != nil || enriched != nil else { return nil }
        var seenNodes = Set<Int64>()
        return ((enriched ?? []) + (explicit ?? [])).filter { item in
            guard item["type"] as? String == "node", let id = item["id"] as? Int64 else { return true }
            return seenNodes.insert(id).inserted
        }
    }

    private static func combined(_ detailed: [[String: Any]]?, _ fallback: [[String: Any]]?) -> [[String: Any]]? {
        guard detailed != nil || fallback != nil else { return nil }
        var nodes = Set<Int64>()
        return ((detailed ?? []) + (fallback ?? [])).filter { item in
            guard item["type"] as? String == "node", let id = item["id"] as? Int64 else { return true }
            return nodes.insert(id).inserted
        }
    }

    private static let postpassSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        return URLSession(configuration: configuration)
    }()

    private static func fetchPostpass(covering points: [LatLng], padding: Double) async -> [[String: Any]]? {
        guard !points.isEmpty, points.allSatisfy({ (-90...90).contains($0.lat) && (-180...180).contains($0.lng) }),
              let south = points.map(\.lat).min(), let north = points.map(\.lat).max(),
              let west = points.map(\.lng).min(), let east = points.map(\.lng).max() else { return nil }
        let dy = padding / 110_000
        let dx = padding / (110_000 * max(0.01, cos(max(abs(south), abs(north)) * .pi / 180)))
        let boxes: [(Double, Double)]
        if east - west > 180 {
            let positive = points.map(\.lng).filter { $0 >= 0 }.min() ?? 180
            let negative = points.map(\.lng).filter { $0 < 0 }.max() ?? -180
            boxes = [(positive - dx, 180), (-180, negative + dx)]
        } else if west - dx < -180 {
            boxes = [(-180, east + dx), (360 + west - dx, 180)]
        } else if east + dx > 180 {
            boxes = [(west - dx, 180), (-180, east + dx - 360)]
        } else {
            boxes = [(west - dx, east + dx)]
        }
        let area = boxes.map {
            "geom && ST_MakeEnvelope(\($0.0),\(max(-90, south - dy)),\($0.1),\(min(90, north + dy)),4326)"
        }.joined(separator: " OR ")
        let query = """
        SELECT geom, osm_id, tags FROM postpass_point
        WHERE (\(area)) AND (
            tags->>'railway' IN ('crossing','level_crossing','tram_level_crossing')
            OR tags->>'highway' IN ('traffic_signals','stop','crossing','give_way')
        ) LIMIT 1800
        """
        var endpoint = URLComponents(string: "https://postpass.geofabrik.de/api/0.2/interpreter")!
        endpoint.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = endpoint.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Kite Maps (road event lookup)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await postpassSession.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return postpassNodes(data)
    }

    static func postpassNodes(_ data: Data) -> [[String: Any]]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["type"] as? String == "FeatureCollection", let features = root["features"] as? [[String: Any]] else { return nil }
        return features.compactMap { feature in
            guard let geometry = feature["geometry"] as? [String: Any], geometry["type"] as? String == "Point",
                  let coords = geometry["coordinates"] as? [Double], coords.count >= 2,
                  let properties = feature["properties"] as? [String: Any],
                  let id = properties["osm_id"] as? Int64, let tags = properties["tags"] as? [String: String] else { return nil }
            return ["type": "node", "id": id, "lat": coords[1], "lon": coords[0], "tags": tags]
        }
    }

    private static func query(around scope: String, walking: Bool) -> String {
        """
        [out:json][timeout:7];
        way["railway"~"^(rail|tram|light_rail|narrow_gauge)$"](around:\(scope))->.tracks;
        way["highway"](around:\(scope))->.roads;
        (
            node["highway"~"^(traffic_signals|stop|crossing|give_way)$"](around:\(scope));
            node["railway"~"^(level_crossing|crossing|tram_level_crossing)$"](around:\(scope));
            node(w.tracks)(w.roads)(around:\(scope));
        )->.controls;
        .controls out body 400;
        \(walking ? "way.roads[oneway~\"^(-1|yes|1|true)$\"]; out body geom 1000; way.roads[highway~\"^(footway|path|pedestrian|steps)$\"]; out body 2000;" : "")

        (way(bn.controls)["highway"];way(bn.controls)["railway"];);
        out body geom 1800;
        """
    }

    private static func nodeControls(_ items: [[String: Any]]) -> [RouteControl] {
        var rail: [Int64: RouteControl.Kind] = [:]
        var road = Set<Int64>()
        for way in items where way["type"] as? String == "way" {
            guard let nodes = way["nodes"] as? [Int64], let tags = way["tags"] as? [String: String] else { continue }
            if tags["highway"] != nil { road.formUnion(nodes) }
            switch tags["railway"] {
            case "tram", "light_rail":
                for id in nodes { rail[id] = .tram }
            case "rail", "narrow_gauge":
                for id in nodes where rail[id] == nil { rail[id] = .railway }
            default: break
            }
        }
        return items.compactMap { item in
            guard item["type"] as? String == "node", let id = item["id"] as? Int64,
                  let point = coordinate(item) else { return nil }
            let tags = item["tags"] as? [String: String] ?? [:]
            let explicit = kind(for: tags)
            let crossing = road.contains(id) ? rail[id] : nil
            guard let type = explicit == .railway ? rail[id] ?? explicit : explicit ?? crossing else { return nil }
            return RouteControl(kind: type, location: point)
        }
    }

    static func kind(for tags: [String: String]) -> RouteControl.Kind? {
        if tags["railway"] == "tram_level_crossing" { return .tram }
        if ["crossing", "level_crossing"].contains(tags["railway"] ?? "") { return .railway }
        switch tags["highway"] {
        case "traffic_signals": return .light
        case "crossing": return .crossing
        case "stop": return .stop
        case "give_way": return .yield
        default: return nil
        }
    }

    public static func lookup(on line: [LatLng], walking: Bool = false) async -> [RouteControl]? {
        let result = await lookupDetailed(on: line, walking: walking)
        return result.controls
    }

    /**
     * [complete] is false when one of the two providers did not answer. Such an answer is useful now
     * (a partial list beats none) but must not be cached as if it were the whole truth.
     */
    public static func lookupDetailed(on line: [LatLng], walking: Bool = false) async -> (controls: [RouteControl]?, complete: Bool) {
        guard line.count >= 2 else { return ([], true) }
        let cumulative = Geo.cumulative(line)
        let length = cumulative.last ?? 0
        let count = max(2, min(150, Int(length / 35) + 1))
        let locale = Locale(identifier: "en_US_POSIX")
        let points = (0..<count).map { index in
            let point = Geo.point(along: line, meters: length * Double(index) / Double(count - 1), cumulative: cumulative)
            return String(format: "%.5f,%.5f", locale: locale, point.lat, point.lng)
        }.joined(separator: ",")
        async let overpass = fetchControls(around: "37,\(points)", walking: walking)
        async let postpass = fetchPostpass(covering: line, padding: 45)
        let (o, p) = await (overpass, postpass)
        guard let items = combined(o, p) else { return (nil, false) }
        return (mapped(items, on: line, cumulative: cumulative, walking: walking), o != nil && p != nil)
    }

    /**
     * The controls that belong to the route, in route order. Driving uses the directional matcher,
     * which reads the OSM way and its direction; walking keeps its own rules for crossings and
     * one-way streets, where a car's approach is not the relevant one.
     */
    static func mapped(_ items: [[String: Any]], on line: [LatLng], cumulative: [Double], walking: Bool = false) -> [RouteControl] {
        if walking { return legacyMapped(items, on: line, cumulative: cumulative, walking: true) }
        return DirectionalRoadControlMatcher.match(elements: items, on: line, cumulative: cumulative)
    }

    private static func legacyMapped(_ items: [[String: Any]], on line: [LatLng], cumulative: [Double], walking: Bool = false) -> [RouteControl] {
        var candidates: [(at: Double, offset: Double, kind: RouteControl.Kind)] = []
        var waysByNode: [Int64: [(before: LatLng?, after: LatLng?, oneway: String?)]] = [:]
        let knownCrossings = Dictionary(nodeControls(items).map { ($0.location, $0.kind) }, uniquingKeysWith: { first, _ in first })
        let pedestrianNodes = Set(items.flatMap { item -> [Int64] in
            guard walking, let tags = item["tags"] as? [String: String],
                  ["footway", "path", "pedestrian", "steps"].contains(tags["highway"] ?? "") else { return [] }
            return item["nodes"] as? [Int64] ?? []
        })
        for way in items where way["type"] as? String == "way" {
            guard let ids = way["nodes"] as? [Int64], let geometry = way["geometry"] as? [[String: Any]],
                  ids.count == geometry.count else { continue }
            let tags = way["tags"] as? [String: String] ?? [:]
            guard tags["highway"] != nil || tags["railway"] == nil else { continue }
            let points = geometry.map(coordinate)
            let oneway = tags["oneway"]
            if walking, ["yes", "1", "true", "-1"].contains(oneway ?? "") {
                // A vertex on the walked route, plus an adjoining segment on that route,
                // distinguishes travelling on the street from merely passing near it.
                let geometry = points.compactMap { $0 }
                let matches = zip(geometry, geometry.dropFirst()).compactMap { a, b -> Double? in
                    guard a.distance(to: b) > 3 else { return nil }
                    let x = Geo.project(a, on: line, cumulative: cumulative)
                    let y = Geo.project(b, on: line, cumulative: cumulative)
                    guard max(x.offset, y.offset) < 7, abs(x.along - y.along) > 3 else { return nil }
                    return min(x.along, y.along)
                }
                if let at = matches.min() { candidates.append((at, 0, .oneWay)) }
                else {
                    for (index, node) in ids.enumerated() where pedestrianNodes.contains(node) {
                        guard let point = points[index] else { continue }
                        let at = Geo.project(point, on: line, cumulative: cumulative)
                        if at.offset < 5 { candidates.append((at.along, at.offset, .oneWay)) }
                    }
                }
            }
            for (index, node) in ids.enumerated() {
                waysByNode[node, default: []].append((index > 0 ? points[index - 1] : nil,
                                                       index + 1 < points.count ? points[index + 1] : nil, oneway))
            }
        }
        for item in items where item["type"] as? String == "node" {
            guard let point = coordinate(item), let id = item["id"] as? Int64, let kind = knownCrossings[point] else { continue }
            let tags = item["tags"] as? [String: String] ?? [:]

            let at = Geo.project(point, on: line, cumulative: cumulative)
            let crossing = kind == .railway || kind == .tram || kind == .crossing
            guard at.offset <= (crossing ? 15 : 12), at.along > 0 else { continue }
            let before = Geo.point(along: line, meters: max(0, at.along - 20), cumulative: cumulative)
            let onRoute = Geo.point(along: line, meters: at.along, cumulative: cumulative)
            let after = Geo.point(along: line, meters: at.along + 12, cumulative: cumulative)
            let ways = waysByNode[id] ?? []
            let direction = tags["traffic_signals:direction"] ?? tags["direction"]
            if !walking, !crossing, !ways.isEmpty {
                let incoming = Geo.bearing(before, before.distance(to: onRoute) > 4 ? onRoute : after)
                let matches = ways.contains { way in
                    let forwardAllowed = way.oneway != "-1" && direction != "backward"
                    let reverseAllowed = !["yes", "1", "true"].contains(way.oneway ?? "") && direction != "forward"
                    return (forwardAllowed && aligned(way.before, with: point, bearing: incoming)) ||
                           (reverseAllowed && aligned(way.after, with: point, bearing: incoming))
                }
                guard matches else { continue }
            } else if !walking && !crossing && (direction != nil || at.offset > 4) {
                continue
            }
            candidates.append((at.along, at.offset, kind))
        }
        var selected: [(at: Double, offset: Double, kind: RouteControl.Kind)] = []
        for candidate in candidates.sorted(by: { $0.at < $1.at }) {
            if let index = selected.lastIndex(where: { $0.kind == candidate.kind && candidate.at - $0.at < 30 }) {
                if candidate.offset < selected[index].offset { selected[index] = candidate }
            } else { selected.append(candidate) }
        }
        return selected.map { RouteControl(kind: $0.kind, location: Geo.point(along: line, meters: $0.at, cumulative: cumulative)) }
    }

    private static func aligned(_ waypoint: LatLng?, with point: LatLng, bearing: Double) -> Bool {
        guard let waypoint, waypoint.distance(to: point) >= 1 else { return false }
        let difference = abs(Geo.bearing(waypoint, point) - bearing)
        return min(difference, 360 - difference) < 40
    }

    private static func coordinate(_ item: [String: Any]) -> LatLng? {
        guard let lat = item["lat"] as? Double, let lng = item["lon"] as? Double else { return nil }
        return LatLng(lat, lng)
    }

    private static func elements(_ data: Data) -> [[String: Any]]? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["elements"] as? [[String: Any]]
    }
}

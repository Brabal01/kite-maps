import Foundation

/**
 * Posted speed limits along a route from the public Valhalla server (FOSSGIS, the same people as
 * the open router), which matches the route to OpenStreetMap's roads and says each one's limit.
 * It answers a whole drive in under a second, where the public Overpass servers can take a minute
 * or not answer at all at night; Overpass still brings the cameras and traffic lights.
 */
public enum Valhalla {
    static let endpoint = URL(string: "https://valhalla1.openstreetmap.de/trace_attributes")!

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.httpAdditionalHeaders = ["User-Agent": OSRM.userAgent, "X-Client-Id": "Brabal01/kite-maps-custom-ios"]
        return URLSession(configuration: c)
    }()

    /** The limits along [line], and the roads it drives (with their limit where known). Nil when the server didn't answer. */
    /// [progress] gets the limits so far after each piece, so a long drive's first miles show straight away.
    public static func speedLimits(along line: [LatLng], progress: (@Sendable ([SpeedLimit]) async -> Void)? = nil) async
        -> (limits: [SpeedLimit], ways: [Overpass.LimitWay], entries: [RoundaboutEntry])? {
        guard line.count >= 2 else { return ([], [], []) }
        let cum = Geo.cumulative(line)
        let total = cum.last ?? 0
        // In pieces of about 25 km: the server turns away very long traces, and placing each road on
        // a short piece of the line is quick.
        var merged: [SpeedLimit] = []
        var ways: [Overpass.LimitWay] = []
        var entries: [RoundaboutEntry] = []
        var start = 0.0
        while start < total {
            let end = min(total, start + 25_000)
            let piece = Geo.slice(line, from: start, to: end, cumulative: cum)
            guard let data = await fetch(thin(piece)), let parsed = parse(data) else { return nil }
            // Placed by where each road really lies on the route; scaled by length (the matched
            // roads run a little longer or shorter) only where that doesn't place it.
            let placed = Overpass.speedLimits(parsed.ways, on: piece)
            let scale = parsed.meters > 0 ? (end - start) / parsed.meters : 1
            for m in stride(from: 0.0, to: end - start, by: 25) {
                let kmh = placed.last { $0.startMeters <= m }?.kmh ?? parsed.limits.last { $0.startMeters * scale <= m }?.kmh
                if merged.last.map({ $0.kmh != kmh }) ?? true { merged.append(SpeedLimit(startMeters: start + m, kmh: kmh)) }
            }
            ways += parsed.ways
            entries += parsed.entries
            start = end
            // Unknown past what has been matched so far, not the last limit carried on.
            if start < total { await progress?(merged + [SpeedLimit(startMeters: start, kmh: nil)]) }
        }
        return (merged, ways, entries)
    }

    /** About one point every 15 m is plenty to match on, and keeps the request small. */
    static func thin(_ line: [LatLng]) -> [LatLng] {
        guard var last = line.first else { return [] }
        var out = [last]
        for p in line.dropFirst() where last.distance(to: p) >= 15 {
            out.append(p)
            last = p
        }
        if let end = line.last, out.last != end { out.append(end) }
        return out
    }

    private static func fetch(_ shape: [LatLng]) async -> Data? {
        let body: [String: Any] = [
            "shape": shape.map { ["lat": $0.lat, "lon": $0.lng] },
            "costing": "auto",
            "shape_match": "map_snap",
            "filters": ["attributes": ["edge.speed_limit", "edge.way_id", "edge.names", "edge.length", "edge.begin_shape_index",
                                       "edge.end_shape_index", "edge.lane_count", "edge.roundabout", "shape"], "action": "include"],
        ]
        var r = URLRequest(url: endpoint)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, resp) = try? await session.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    /** Limit changes along the matched roads (meters from their start), the roads themselves, and their length. */
    static func parse(_ data: Data) -> (limits: [SpeedLimit], ways: [Overpass.LimitWay], meters: Double, entries: [RoundaboutEntry])? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let edges = root["edges"] as? [[String: Any]] else { return nil }
        let shape = (root["shape"] as? String).map { Geo.decodePolyline($0) } ?? []
        var limits: [SpeedLimit] = []
        var ways: [Overpass.LimitWay] = []
        var along = 0.0
        // The last posted limit and the road it was on.
        var carried: (kmh: Double, names: Set<String>)?
        var entries: [RoundaboutEntry] = []
        for (k, e) in edges.enumerated() {
            // The road in to a roundabout: its lanes where it meets the circle.
            if (e["roundabout"] as? Bool) != true, k + 1 < edges.count, (edges[k + 1]["roundabout"] as? Bool) == true,
               let lanes = (e["lane_count"] as? NSNumber)?.intValue, (1...6).contains(lanes),
               let b = (e["end_shape_index"] as? NSNumber)?.intValue, shape.indices.contains(b) {
                entries.append(RoundaboutEntry(at: shape[b], lanes: lanes))
            }
            // 0 is "not known"; Valhalla marks a variable or no limit with 255.
            let raw = (e["speed_limit"] as? NSNumber)?.doubleValue
            let mapped = Overpass.britishLimit(raw.flatMap { (1...200).contains($0) ? $0 : nil }, at: shape.first ?? LatLng(0, 0))
            let names = Set((e["names"] as? [String]) ?? [])
            // A limit holds until a sign says otherwise: further along the same road with no limit
            // mapped, the last one still applies (Normandy Way, Marchwood: 40 mph mapped by the
            // roundabout, then a mile with none, 2026-10-27). A different road starts unknown.
            if let m = mapped, !names.isEmpty { carried = (m, names) }
            else if mapped == nil, let c = carried, names.isDisjoint(with: c.names) { carried = nil }
            else if mapped != nil { carried = nil }
            let kmh = mapped ?? carried?.kmh
            if limits.last.map({ $0.kmh != kmh }) ?? true { limits.append(SpeedLimit(startMeters: along, kmh: kmh)) }
            along += ((e["length"] as? NSNumber)?.doubleValue ?? 0) * 1000
            if let a = (e["begin_shape_index"] as? NSNumber)?.intValue, let b = (e["end_shape_index"] as? NSNumber)?.intValue,
               a >= 0, b < shape.count, b > a {
                // The roads keep only what's mapped (they're remembered for later drives); the carried limit is in [limits].
                ways.append(Overpass.LimitWay(id: (e["way_id"] as? NSNumber)?.int64Value ?? 0, kmh: mapped, line: Array(shape[a...b])))
            }
        }
        return (limits, ways, along, entries)
    }
}

/** Where the route meets a roundabout, and how many lanes the road in has there (from the road matcher). */
public struct RoundaboutEntry: Hashable, Sendable {
    public var at: LatLng
    public var lanes: Int
}

extension Valhalla {
    private struct Coordinates: Encodable {
        let lat: Double
        let lon: Double
        init(_ point: LatLng) { lat = point.lat; lon = point.lng }
    }

    private struct RouteRequest: Encodable {
        let locations: [Coordinates]
        let costing: String
        let costing_options: [String: Preferences]
        let alternates: Int
        let units = "kilometers"
    }

    private struct Preferences: Encodable {
        var bicycle_type: String? = nil
        var use_roads: Double? = nil
        var walkway_factor: Double? = nil
        var sidewalk_factor: Double? = nil
        var alley_factor: Double? = nil
        var walking_speed: Double? = nil
        var use_tolls: Double? = nil
        var use_highways: Double? = nil
    }

    private struct Response: Decodable {
        let trip: Trip
        let alternates: [Response]?
    }

    private struct Trip: Decodable {
        struct Summary: Decodable {
            let length: Double
            let time: Double
            let hasHighway: Bool?
            let hasToll: Bool?
        }
        struct Leg: Decodable {
            struct Turn: Decodable {
                let type: Int
                let instruction: String
                let streetNames: [String]?
                let beginShapeIndex: Int
                let endShapeIndex: Int
                let roundaboutExitCount: Int?
            }
            let shape: String
            let maneuvers: [Turn]
        }
        let summary: Summary
        let legs: [Leg]
    }

    public static var walkingSpeed: Double {
        let value = UserDefaults.standard.double(forKey: "walkingSpeed")
        return (2...8).contains(value) ? value : 5
    }

    static func activeRoutes(_ points: [LatLng], mode: TravelMode, alternatives: Bool) async -> [Route] {
        guard mode != .drive, points.count >= 2 else { return [] }
        let costing = mode == .bike ? "bicycle" : "pedestrian"
        let preferences = mode == .bike ? Preferences(bicycle_type: "hybrid", use_roads: 0)
            : Preferences(walkway_factor: 0.45, sidewalk_factor: 0.60, alley_factor: 1.0, walking_speed: walkingSpeed)
        let body = RouteRequest(locations: points.map(Coordinates.init), costing: costing,
                                costing_options: [costing: preferences],
                                alternates: alternatives && points.count == 2 ? 2 : 0)
        guard let data = await request("route", body: body) else { return [] }
        return parseRoutes(data, mode: mode, points: points)
    }

    static func avoidingRoutes(_ points: [LatLng], avoidHighways: Bool, avoidTolls: Bool,
                               alternatives: Bool) async -> [Route] {
        let preferences = Preferences(use_tolls: avoidTolls ? 0 : nil,
                                      use_highways: avoidHighways ? 0 : nil)
        let body = RouteRequest(locations: points.map(Coordinates.init), costing: "auto",
                                costing_options: ["auto": preferences],
                                alternates: alternatives && points.count == 2 ? 2 : 0)
        guard let data = await request("route", body: body) else { return [] }
        return parseRoutes(data, mode: .drive, points: points)
    }

    static func parseRoutes(_ data: Data, mode: TravelMode, points: [LatLng]) -> [Route] {
        guard let answer = try? decoder().decode(Response.self, from: data) else { return [] }
        return ([answer] + (answer.alternates ?? [])).compactMap { response in
            let trip = response.trip
            guard mode == .drive || trip.summary.hasHighway != true else { return nil }
            var line: [LatLng] = []
            var turns: [Maneuver] = []
            var length = 0.0
            var roads: [String: Double] = [:]
            for (i, leg) in trip.legs.enumerated() {
                let shape = Geo.decodePolyline(leg.shape)
                guard shape.count >= 2 else { return nil }
                let cumulative = Geo.cumulative(shape)
                if line.last == shape.first { line.append(contentsOf: shape.dropFirst()) }
                else { line.append(contentsOf: shape) }
                for turn in leg.maneuvers {
                    guard shape.indices.contains(turn.beginShapeIndex), shape.indices.contains(turn.endShapeIndex),
                          turn.beginShapeIndex <= turn.endShapeIndex else { return nil }
                    let type = kind(turn.type)
                    if (type == .arrive && i < trip.legs.count - 1) || (type == .depart && i > 0) { continue }
                    let distance = cumulative[turn.endShapeIndex] - cumulative[turn.beginShapeIndex]
                    let road = turn.streetNames?.first
                    if let road { roads[road, default: 0] += distance }
                    turns.append(Maneuver(type: type, instruction: turn.instruction, location: shape[turn.beginShapeIndex],
                                          alongMeters: length + cumulative[turn.beginShapeIndex], distanceMeters: distance,
                                          road: road, exit: turn.roundaboutExitCount))
                }
                length += cumulative.last ?? 0
            }
            guard fitsActiveRoute(line, points: points), !turns.isEmpty else { return nil }
            let duration = trip.summary.time
            return Route(mode: mode, polyline: line, distanceMeters: trip.summary.length * 1_000,
                         typicalSeconds: duration, trafficSeconds: nil, summary: roads.max { $0.value < $1.value }?.key,
                         maneuvers: turns, source: "osm", routerReportedTolls: trip.summary.hasToll)
        }
    }

    static func fitsActiveRoute(_ line: [LatLng], points: [LatLng]) -> Bool {
        guard line.count >= 2, points.count >= 2, let start = line.first, let end = line.last,
              start.distance(to: points[0]) < 150, end.distance(to: points[points.count - 1]) < 150 else { return false }
        let nearby = NearLine(line)
        return points.dropFirst().dropLast().allSatisfy { nearby.project($0).offset <= 100 }
    }

    private static func kind(_ value: Int) -> ManeuverType {
        switch value {
        case 1...3: return .depart
        case 4...6: return .arrive
        case 7, 8, 17: return .straight
        case 9: return .slightRight
        case 10: return .turnRight
        case 11: return .sharpRight
        case 12, 13: return .uturn
        case 14: return .sharpLeft
        case 15: return .turnLeft
        case 16: return .slightLeft
        case 18, 20: return .rampRight
        case 19, 21: return .rampLeft
        case 22: return .straight
        case 23: return .keepRight
        case 24: return .keepLeft
        case 25, 37, 38: return .merge
        case 26: return .roundabout
        default: return .unknown
        }
    }

    private struct TraceRequest: Encodable {
        struct Filter: Encodable {
            let attributes = ["edge.toll", "edge.begin_shape_index", "edge.end_shape_index", "shape"]
            let action = "include"
        }
        let shape: [Coordinates]
        let shape_match = "walk_or_snap"
        let costing = "auto"
        let filters = Filter()
    }

    private struct TraceResponse: Decodable {
        struct Edge: Decodable {
            let toll: Bool?
            let beginShapeIndex: Int
            let endShapeIndex: Int
        }
        let shape: String
        let edges: [Edge]
    }

    static func toll(on line: [LatLng]) async -> Bool {
        await verifiedToll(on: line) == true
    }

    static func verifiedToll(on line: [LatLng]) async -> Bool? {
        let pieces = Overpass.pieces(line, meters: 25_000)
        guard !pieces.isEmpty else { return nil }
        return await withTaskGroup(of: Bool?.self) { group in
            var allPiecesVerified = true
            var next = 0
            while next < min(2, pieces.count) {
                let piece = pieces[next]
                group.addTask { await tollPiece(piece) }
                next += 1
            }
            while let found = await group.next(), !Task.isCancelled {
                if found == true { group.cancelAll(); return true }
                if found == nil { allPiecesVerified = false }
                if next < pieces.count {
                    let piece = pieces[next]
                    group.addTask { await tollPiece(piece) }
                    next += 1
                }
            }
            return allPiecesVerified && !Task.isCancelled ? false : nil
        }
    }

    private static func tollPiece(_ line: [LatLng]) async -> Bool? {
        guard line.count >= 2 else { return nil }
        let thinned = thin(line)
        let count = max(1, (thinned.count + 699) / 700)
        let shape = stride(from: 0, to: thinned.count - 1, by: count).map { Coordinates(thinned[$0]) }
            + [Coordinates(thinned[thinned.count - 1])]
        guard let data = await request("trace_attributes", body: TraceRequest(shape: shape)) else { return nil }
        return tollEvidence(data, on: line)
    }

    static func confirmsToll(_ data: Data, on line: [LatLng]) -> Bool {
        tollEvidence(data, on: line) == true
    }

    static func tollEvidence(_ data: Data, on line: [LatLng]) -> Bool? {
        guard line.count >= 2, let trace = try? decoder().decode(TraceResponse.self, from: data),
              !trace.edges.isEmpty else { return nil }
        let matched = Geo.decodePolyline(trace.shape)
        let route = NearLine(line)
        for edge in trace.edges where edge.toll == true {
            guard matched.indices.contains(edge.beginShapeIndex), matched.indices.contains(edge.endShapeIndex),
                  edge.beginShapeIndex < edge.endShapeIndex else { continue }
            let slice = Array(matched[edge.beginShapeIndex...edge.endShapeIndex])
            let cumulative = Geo.cumulative(slice)
            let length = cumulative.last ?? 0
            guard length > 0 else { continue }
            let samples = max(2, Int(ceil(length / 35)))
            var previous: Double?
            for i in 0...samples {
                let point = Geo.point(along: slice, meters: length * Double(i) / Double(samples), cumulative: cumulative)
                let hit = route.project(point)
                guard hit.offset <= 22 else { previous = nil; continue }
                if let previous, hit.along - previous >= 0.7 * length / Double(samples) { return true }
                previous = hit.along
            }
        }
        // Only report a negative when the trace covers the actual route and every edge is
        // explicitly free. A snapped parallel road, network error or partial trace is unknown.
        guard !trace.edges.contains(where: { $0.toll != false }),
              trace.edges.first?.beginShapeIndex == 0, trace.edges.last?.endShapeIndex == matched.count - 1,
              zip(trace.edges, trace.edges.dropFirst()).allSatisfy({ $0.0.endShapeIndex == $0.1.beginShapeIndex }),
              followsEntireLine(matched, reference: line), followsEntireLine(line, reference: matched)
        else { return nil }
        return false
    }

    private static func followsEntireLine(_ line: [LatLng], reference: [LatLng]) -> Bool {
        guard let start = line.first, let end = line.last, let refStart = reference.first, let refEnd = reference.last,
              line.count >= 2, reference.count >= 2,
              start.distance(to: refStart) < 20, end.distance(to: refEnd) < 20 else { return false }
        let matchingLine = NearLine(reference)
        let cumulative = Geo.cumulative(line)
        guard let length = cumulative.last, length > 0 else { return false }
        let steps = max(2, Int(ceil(length / 25)))
        var latest = 0.0
        for step in 0...steps {
            let point = Geo.point(along: line, meters: Double(step) * length / Double(steps), cumulative: cumulative)
            let projection = matchingLine.project(point)
            guard projection.offset <= 12, projection.along + 12 >= latest else { return false }
            latest = max(latest, projection.along)
        }
        return true
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private static func request<T: Encodable>(_ path: String, body: T) async -> Data? {
        guard let json = try? JSONEncoder().encode(body) else { return nil }
        let url = endpoint.deletingLastPathComponent().appendingPathComponent(path)
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = json
        if let (data, response) = try? await session.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200 { return data }
        // The public instance also accepts GET for small requests.
        guard !Task.isCancelled, json.count < 2_000, let payload = String(data: json, encoding: .utf8),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "json", value: payload)]
        guard let url = components.url, let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}

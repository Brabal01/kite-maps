import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct TransitCall: Hashable, Sendable {
    public let id: String?
    public let name: String
    public let location: LatLng
    public let arrival: Date?
    public let departure: Date?
    public let platform: String?
    public let arrivalDelay: Int?
    public let departureDelay: Int?
    public var cancelled = false
}

/** One part of a transit trip: a walk, or a ride on one line between two stops. */
public struct TransitLeg: Hashable, Sendable {
    public var isWalk: Bool
    /** "SUBWAY", "BUS", "TRAM", "RAIL"…, as the planner names it. */
    public var mode: String
    /** The line's short name ("N", "38R"), empty for a walk. */
    public var line: String
    /** The agency's own colors, 0xRRGGBB, when it publishes them. */
    public var color: UInt32?
    public var textColor: UInt32?
    public var headsign: String?
    public var fromName: String
    public var toName: String
    public var depart: Date?
    public var arrive: Date?
    public var durationSeconds: Double
    public var distanceMeters: Double
    public var stops: Int
    /** Minutes late (or early, below zero) when the agency sends live times. */
    public var delayMinutes: Int?
    public var path: [LatLng]
    public var calls: [TransitCall] = []
    public var tripID: String?
    public var cancelled = false
    public var alerts: [String] = []

    public init(isWalk: Bool, mode: String, line: String = "", color: UInt32? = nil, textColor: UInt32? = nil,
                headsign: String? = nil, fromName: String = "", toName: String = "", depart: Date? = nil,
                arrive: Date? = nil, durationSeconds: Double = 0, distanceMeters: Double = 0, stops: Int = 0,
                delayMinutes: Int? = nil, path: [LatLng] = []) {
        self.isWalk = isWalk; self.mode = mode; self.line = line; self.color = color; self.textColor = textColor
        self.headsign = headsign; self.fromName = fromName; self.toName = toName; self.depart = depart
        self.arrive = arrive; self.durationSeconds = durationSeconds; self.distanceMeters = distanceMeters
        self.stops = stops; self.delayMinutes = delayMinutes; self.path = path
    }

    /** What kind of vehicle, for an icon. */
    public var vehicle: Vehicle { Vehicle(mode) }

    public enum Vehicle: Sendable {
        case walk, bus, metro, tram, train, ferry, other
        init(_ mode: String) {
            switch mode {
            case "WALK", "BIKE", "CAR", "RENTAL": self = .walk
            case "BUS", "COACH", "ODM", "FLEX": self = .bus
            case "SUBWAY", "METRO": self = .metro
            case "TRAM", "CABLE_CAR", "FUNICULAR", "AERIAL_LIFT": self = .tram
            case "FERRY": self = .ferry
            default: self = mode.contains("RAIL") || mode == "SUBURBAN" || mode == "LONG_DISTANCE" ? .train : .other
            }
        }
    }
}

/** One way to get there by public transit. */
public struct TransitTrip: Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var depart: Date?
    public var arrive: Date?
    public var durationSeconds: Double
    public var transfers: Int
    public var legs: [TransitLeg]
    public var itineraryID: String?
    public var lineKeys: [String] { rides.map { "\($0.mode):\($0.line)" } }

    public init(depart: Date?, arrive: Date?, durationSeconds: Double, transfers: Int, legs: [TransitLeg]) {
        self.depart = depart; self.arrive = arrive; self.durationSeconds = durationSeconds
        self.transfers = transfers; self.legs = legs
    }

    public var rides: [TransitLeg] { legs.filter { !$0.isWalk } }
    public var walkSeconds: Double { legs.filter(\.isWalk).map(\.durationSeconds).reduce(0, +) }
    /** The whole trip's shape, for framing the map. */
    public var path: [LatLng] { legs.flatMap(\.path) }
}

/**
 * Public transit directions from Transitous (transitous.org), the community-run planner over
 * the world's open timetables that Vela uses: keyless, with live delays where agencies send them.
 */
public enum Transitous {
    public static let base = "https://api.transitous.org"

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 25
        c.httpAdditionalHeaders = ["User-Agent": "Kite-Driving-iOS (https://github.com/Gordicek/kite-maps)"]
        return URLSession(configuration: c)
    }()

    public static func planURL(from: LatLng, to: LatLng, max: Int = 5, time: Date? = nil, arriveBy: Bool = false) -> URL? {
        var s = "\(base)/api/v1/plan?fromPlace=\(from.lat.plain),\(from.lng.plain)&toPlace=\(to.lat.plain),\(to.lng.plain)&numItineraries=\(max)"
        if let time {
            let f = ISO8601DateFormatter()
            s += "&time=" + f.string(from: time)
            if arriveBy { s += "&arriveBy=true" }
        }
        return URL(string: s)
    }

    /** Trips leaving now, or around [time] (arriving by it when [arriveBy]). Throws on a network error. */
    public static func plan(from: LatLng, to: LatLng, time: Date? = nil, arriveBy: Bool = false) async throws -> [TransitTrip] {
        guard let url = planURL(from: from, to: to, time: time, arriveBy: arriveBy) else { return [] }
        if let latest = URL(string: url.absoluteString.replacingOccurrences(of: "/api/v1/", with: "/api/v6/") + "&withFares=false"),
           let data = await get(latest) { return parse(data) }
        let (data, resp) = try await session.data(from: url)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw URLError(.badServerResponse) }
        return parse(data)
    }

    /** One upcoming departure at a stop. */
    public struct Departure: Hashable, Sendable {
        public var line: String
        public var mode: String
        public var color: UInt32?
        public var textColor: UInt32?
        public var headsign: String
        public var time: Date
        /** Minutes late, when the agency sends live times. */
        public var delayMinutes: Int?
        public var platform: String?
        public var tripID: String?
        public var vehicle: TransitLeg.Vehicle { TransitLeg.Vehicle(mode) }
    }

    /**
     * The departure board for the stop nearest [point] (within about [radius] meters), the way
     * Vela reads it: the stop's parent station, so every platform of a hub is on one board.
     * Nil when there is no stop or no service.
     */
    public static func departures(near point: LatLng, radius: Double = 150) async -> (stop: String, departures: [Departure])? {
        let dLat = radius / 111_320, dLng = radius / (111_320 * cos(point.lat * .pi / 180))
        guard let url = URL(string: "\(base)/api/v1/map/stops?min=\(point.lat - dLat),\(point.lng - dLng)&max=\(point.lat + dLat),\(point.lng + dLng)"),
              let (data, _) = try? await session.data(from: url),
              let stops = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let nearest = stops.compactMap { s -> (name: String, id: String, d: Double)? in
            guard let id = (s["parentId"] as? String) ?? (s["stopId"] as? String), let p = Self.point(s) else { return nil }
            return (s["name"] as? String ?? "", id, p.distance(to: point))
        }.sorted { $0.d < $1.d }
        guard let first = nearest.first else { return nil }
        // The two curbs of a street often are two stops with one name: show both on one board.
        let ids = Array(Set(nearest.filter { $0.name == first.name || $0.d - first.d < 25 }.map(\.id))).prefix(4)
        var all: [Departure] = []
        for id in ids {
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            guard let u = URL(string: "\(base)/api/v1/stoptimes?stopId=\(id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id)&n=30"),
                  let (d, _) = try? await session.data(from: u) else { continue }
            all += parseStopTimes(d, stopName: first.name)
        }
        guard !all.isEmpty else { return nil }
        var seen = Set<String>()
        let board = all.sorted { $0.time < $1.time }.filter { seen.insert("\($0.line)|\($0.headsign)|\($0.time.timeIntervalSince1970)").inserted }
        return (first.name, board)
    }

    public static func parseStopTimes(_ data: Data, stopName: String = "") -> [Departure] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["stopTimes"] as? [[String: Any]] else { return [] }
        return list.compactMap { st in
            let place = st["place"] as? [String: Any] ?? [:]
            if st["tripCancelled"] as? Bool == true || place["cancelled"] as? Bool == true { return nil }
            guard let time = date(place["departure"]) else { return nil }
            var delay: Int?
            if st["realTime"] as? Bool == true, let sched = date(place["scheduledDeparture"]) {
                delay = Int((time.timeIntervalSince(sched) / 60).rounded())
            }
            let line = [st["routeShortName"], st["displayName"], st["routeLongName"]]
                .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
            // Where the run ends. Some feeds put the stop's own name in the headsign, so the trip's
            // last stop wins; a run that ends here isn't a departure.
            let end = (st["tripTo"] as? [String: Any])?["name"] as? String
            if let end, !stopName.isEmpty, end == stopName { return nil }
            var headsign = st["headsign"] as? String ?? ""
            if let end, !end.isEmpty, headsign.isEmpty || headsign == stopName { headsign = end }
            return Departure(line: line, mode: st["mode"] as? String ?? "", color: hex(st["routeColor"]),
                             textColor: hex(st["routeTextColor"]), headsign: headsign,
                             time: time, delayMinutes: delay, platform: platform(place), tripID: st["tripId"] as? String)
        }
    }

    public struct Stop: Identifiable, Hashable, Sendable {
        public let id: String
        public let location: LatLng
        public let name: String
    }

    public static func nearbyStops(_ at: LatLng, radius: Double = 900) async -> [Stop]? {
        let dLat = radius / 111_320, dLng = radius / (111_320 * max(0.1, cos(at.lat * .pi / 180)))
        guard let url = URL(string: "\(base)/api/v1/map/stops?min=\(at.lat - dLat),\(at.lng - dLng)&max=\(at.lat + dLat),\(at.lng + dLng)&grouped=true"),
              let data = await get(url),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let nearby = rows.compactMap { row -> Stop? in
            guard let at = point(row), let raw = row["stopId"] as? String else { return nil }
            let parent = (row["parentId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return Stop(id: parent ?? raw, location: at, name: row["name"] as? String ?? "Stop")
        }.filter { $0.location.distance(to: at) <= radius }.sorted { $0.location.distance(to: at) < $1.location.distance(to: at) }
        var seen = Set<String>()
        return Array(nearby.filter { seen.insert($0.id).inserted }.prefix(8))
    }

    public static func departures(at stop: Stop) async -> [Departure]? {
        for version in [6, 5, 1] {
            guard let u = endpoint(version, "stoptimes", ["stopId": stop.id, "n": "30"]), let data = await get(u) else { continue }
            return parseStopTimes(data, stopName: stop.name).sorted { $0.time < $1.time }
        }
        return nil
    }

    public static func refresh(_ trip: TransitTrip) async -> TransitTrip? {
        guard let id = trip.itineraryID,
              let u = endpoint(6, "refresh-itinerary", ["itineraryId": id, "withFares": "false"]),
              let data = await get(u),
              let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var updated = itinerary(row),
              updated.rides.map(\.tripID) == trip.rides.map(\.tripID) else { return nil }
        updated.id = trip.id
        updated.itineraryID = updated.itineraryID ?? id
        return updated
    }

    public struct VehiclePosition: Sendable {
        public let location: LatLng
        public let isGPS: Bool
        public let occupancy: String?
    }

    public static func livePosition(for selected: TransitLeg) async -> VehiclePosition? {
        guard let id = selected.tripID,
              let u = endpoint(6, "trip", ["tripId": id, "withScheduledSkippedStops": "true"]),
              let data = await get(u),
              let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = (row["legs"] as? [[String: Any]])?.first(where: { $0["tripId"] as? String == id }),
              raw["realTime"] as? Bool == true, raw["cancelled"] as? Bool != true else { return nil }
        let current = leg(raw)
        let now = Date()
        if let position = raw["vehiclePosition"] as? [String: Any],
           let at = point(position), let stamp = date(position["timestamp"]),
           abs(now.timeIntervalSince(stamp)) < 90 {
            return VehiclePosition(location: at, isGPS: true, occupancy: position["occupancyStatus"] as? String)
        }
        let cumulative = Geo.cumulative(current.path)
        guard current.path.count >= 2 else { return nil }
        let calls = current.calls.filter { !$0.cancelled }
        for (a, b) in zip(calls, calls.dropFirst()) {
            guard let start = a.departure, let end = b.arrival, end > start, (start...end).contains(now),
                  a.departureDelay != nil || b.arrivalDelay != nil else { continue }
            let from = Geo.project(a.location, on: current.path, cumulative: cumulative)
            let to = Geo.project(b.location, on: current.path, cumulative: cumulative)
            guard from.offset < 150, to.offset < 150, from.along <= to.along else { return nil }
            let fraction = now.timeIntervalSince(start) / end.timeIntervalSince(start)
            let at = Geo.point(along: current.path, meters: from.along + fraction * (to.along - from.along), cumulative: cumulative)
            return VehiclePosition(location: at, isGPS: false, occupancy: nil)
        }
        return nil
    }

    private static func endpoint(_ version: Int, _ path: String, _ query: [String: String]) -> URL? {
        var parts = URLComponents(string: "\(base)/api/v\(version)/\(path)")
        parts?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return parts?.url
    }

    private static func get(_ url: URL) async -> Data? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    /** A stretch of metro or rail track with its lines' color, for the transit map layer. */
    public struct Line: Sendable {
        public var points: [LatLng]
        public var color: UInt32
        public var metro: Bool
        public var names: [String]
    }

    /**
     * Metro, tram and train lines in a box, from Transitous' route map (Vela's transit layer).
     * Buses are left out. Below zoom 9 the service sends long-distance rail only.
     */
    public static func lines(south: Double, west: Double, north: Double, east: Double, zoom: Int) async -> [Line]? {
        guard let url = URL(string: "\(base)/api/experimental/map/routes?min=\(south),\(west)&max=\(north),\(east)&zoom=\(zoom)"),
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parseLines(data)
    }

    public static func parseLines(_ data: Data) -> [Line] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let routes = root["routes"] as? [[String: Any]],
              let polys = root["polylines"] as? [[String: Any]] else { return [] }
        var out: [Line] = []
        for p in polys {
            let rs = (p["routeIndexes"] as? [Int] ?? []).compactMap { routes.indices.contains($0) ? routes[$0] : nil }
            let rail = rs.filter { r in
                let v = TransitLeg.Vehicle(r["mode"] as? String ?? "")
                return v == .metro || v == .tram || v == .train
            }
            guard !rail.isEmpty, let enc = p["polyline"] as? [String: Any], let pts = enc["points"] as? String else { continue }
            let color = rail.lazy.compactMap { r in hex((r["transitRoutes"] as? [[String: Any]])?.first?["color"]) }.first
            let metro = rail.contains { TransitLeg.Vehicle($0["mode"] as? String ?? "") != .train }
            let names = rail.compactMap { ($0["transitRoutes"] as? [[String: Any]])?.first?["shortName"] as? String }
            let precision = min(7, max(5, (enc["precision"] as? Int) ?? 6))
            let line = Geo.decodePolyline(pts, precision: pow(10, Double(precision)))
            guard line.count >= 2 else { continue }
            // A feed without shapes draws straight chords between distant stops: leave those out.
            let len = Geo.length(line)
            if !metro, len / Double(line.count - 1) > 700 { continue }
            out.append(Line(points: line, color: color ?? (metro ? 0x5F6368 : 0x8E8E93), metro: metro,
                            names: Array(Set(names)).sorted()))
        }
        return out
    }

    public static func parse(_ data: Data) -> [TransitTrip] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let its = root["itineraries"] as? [[String: Any]] else { return [] }
        let trips = its.compactMap(itinerary)
        // The planner can repeat a trip; keep the first of each line-up and time.
        var seen = Set<String>()
        return trips.filter { t in
            let key = t.rides.map(\.line).joined(separator: ",") + "\(t.depart?.timeIntervalSince1970 ?? 0)"
            return seen.insert(key).inserted
        }
    }

    private static func itinerary(_ it: [String: Any]) -> TransitTrip? {
        guard let rawLegs = it["legs"] as? [[String: Any]] else { return nil }
        let legs = rawLegs.map(leg)
        guard legs.contains(where: { !$0.isWalk }) else { return nil } // a walk-only answer isn't transit
        let start = date(it["startTime"]), end = date(it["endTime"])
        let dur = number(it["duration"]) ?? (start.flatMap { s in end.map { $0.timeIntervalSince(s) } } ?? 0)
        let transfers = (it["transfers"] as? Int) ?? max(0, legs.filter { !$0.isWalk }.count - 1)
        var trip = TransitTrip(depart: start, arrive: end, durationSeconds: dur, transfers: transfers, legs: legs)
        trip.itineraryID = (it["id"] ?? it["itineraryId"]) as? String
        return trip
    }

    private static func leg(_ l: [String: Any]) -> TransitLeg {
        let mode = l["mode"] as? String ?? ""
        let from = l["from"] as? [String: Any] ?? [:], to = l["to"] as? [String: Any] ?? [:]
        let start = date(l["startTime"]), end = date(l["endTime"])
        let dur = number(l["duration"]) ?? (start.flatMap { s in end.map { $0.timeIntervalSince(s) } } ?? 0)
        var out = TransitLeg(isWalk: TransitLeg.Vehicle(mode) == .walk, mode: mode,
                             fromName: from["name"] as? String ?? "", toName: to["name"] as? String ?? "",
                             depart: start, arrive: end, durationSeconds: dur,
                             distanceMeters: number(l["distance"]) ?? 0, path: path(l))
        if out.path.count < 2, let a = point(from), let b = point(to) { out.path = [a, b] }
        if out.isWalk {
            if out.distanceMeters == 0 { out.distanceMeters = Geo.length(out.path) }
            return out
        }
        out.line = [l["routeShortName"], l["displayName"], l["routeLongName"]]
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        out.color = hex(l["routeColor"])
        out.textColor = hex(l["routeTextColor"])
        out.headsign = (l["headsign"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let intermediate = l["intermediateStops"] as? [[String: Any]] ?? []
        out.stops = intermediate.count + 1
        out.tripID = l["tripId"] as? String
        out.cancelled = l["cancelled"] as? Bool == true
        let live = l["realTime"] as? Bool == true
        let rows = [from] + intermediate + [to]
        out.calls = rows.compactMap { call($0, live: live) }
        out.cancelled = out.cancelled || out.calls.first?.cancelled == true || out.calls.last?.cancelled == true
        let notices = ([l] + rows).flatMap { $0["alerts"] as? [[String: Any]] ?? [] }
        out.alerts = Array(Set(notices.compactMap { ($0["alertHeaderText"] ?? $0["headerText"] ?? $0["descriptionText"]) as? String })).sorted()
        if [.tram, .metro, .train].contains(out.vehicle) {
            out.path = withoutRailSpikes(out.path, calls: out.calls)
        }
        if out.distanceMeters == 0 { out.distanceMeters = Geo.length(out.path) }
        out.delayMinutes = out.calls.first?.departureDelay ?? delay(start, l["scheduledStartTime"], live: live)
        return out
    }

    static func withoutRailSpikes(_ path: [LatLng], calls: [TransitCall]) -> [LatLng] {
        guard path.count >= 3, calls.count >= 2 else { return path }
        return path.enumerated().compactMap { i, point in
            guard i > 0, i < path.count - 1 else { return point }
            let before = path[i - 1], after = path[i + 1]
            let shorterSide = min(before.distance(to: point), point.distance(to: after))
            if shorterSide >= 120, before.distance(to: after) < 0.5 * shorterSide,
               !calls.contains(where: { $0.location.distance(to: point) <= 45 }) { return nil }
            return point
        }
    }

    private static func call(_ row: [String: Any], live: Bool) -> TransitCall? {
        guard let at = point(row) else { return nil }
        let a = date(row["arrival"]), d = date(row["departure"])
        return TransitCall(id: row["stopId"] as? String, name: row["name"] as? String ?? "", location: at,
                           arrival: a, departure: d, platform: platform(row),
                           arrivalDelay: delay(a, row["scheduledArrival"], live: live, reason: row["arrivalTimestampReason"]),
                           departureDelay: delay(d, row["scheduledDeparture"], live: live, reason: row["departureTimestampReason"]),
                           cancelled: row["cancelled"] as? Bool == true)
    }

    private static func platform(_ row: [String: Any]) -> String? {
        ((row["track"] ?? row["scheduledTrack"]) as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func delay(_ actual: Date?, _ scheduled: Any?, live: Bool, reason: Any? = nil) -> Int? {
        guard live, let actual, let earlier = date(scheduled),
              !["NO_RT_DATA", "INCONSISTENT_RT"].contains(reason as? String ?? "") else { return nil }
        return Int((actual.timeIntervalSince(earlier) / 60).rounded())
    }

    private static func path(_ l: [String: Any]) -> [LatLng] {
        guard let g = l["legGeometry"] as? [String: Any], let pts = g["points"] as? String, !pts.isEmpty else { return [] }
        let p = min(7, max(5, (g["precision"] as? Int) ?? 6))
        return Geo.decodePolyline(pts, precision: pow(10, Double(p)))
            .filter { (-90...90).contains($0.lat) && (-180...180).contains($0.lng) }
    }

    private static func point(_ o: [String: Any]) -> LatLng? {
        guard let lat = number(o["lat"]), let lon = number(o["lon"]) else { return nil }
        return LatLng(lat, lon)
    }

    private static func number(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }

    static func hex(_ v: Any?) -> UInt32? {
        guard var s = (v as? String)?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        return s.count == 6 ? UInt32(s, radix: 16) : nil
    }

    static func date(_ v: Any?) -> Date? {
        guard let s = v as? String, !s.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}

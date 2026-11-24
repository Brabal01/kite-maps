import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/** How fresh a leg's live data is. */
public enum TransitLiveFreshness: String, Hashable, Sendable {
    case live
    case recent
    case stale
    case scheduled
    case unavailable
}

/** A vehicle position from GTFS-Realtime, when the feed sends one. */
public struct TransitVehicle: Hashable, Sendable {
    public var location: LatLng
    public var bearing: Double?
    public var speedMps: Double?
    public var updated: Date?
    public init(location: LatLng, bearing: Double? = nil, speedMps: Double? = nil, updated: Date? = nil) {
        self.location = location
        self.bearing = bearing
        self.speedMps = speedMps
        self.updated = updated
    }
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
    public var boardStop: TransitCall?
    public var exitStop: TransitCall?
    public var intermediateStops: [TransitCall] = []
    public var walkSteps: [TransitWalkStep] = []
    public var agency: String?
    public var serviceNumber: String?
    public var arrivalDelayMinutes: Int?
    public var serviceAlerts: [String] = []
    public var destinationStop: LatLng?
    /** The planner's trip identifier, used to join an optional GTFS-Realtime feed. */
    public var tripId: String?
    /** The planner's route identifier, for route-wide live alerts. */
    public var routeId: String?
    /** The scheduled departure from the first stop, used to match GTFS-Realtime identities. */
    public var scheduledDepart: Date?
    /** GTFS direction id (0/1), when the planner or live feed provides it. */
    public var directionId: Int?
    /** Agency id used by the live feed, when available. */
    public var agencyId: String?
    /** Freshness of the live data attached to this leg. */
    public var liveFreshness: TransitLiveFreshness = .scheduled
    /** Age of the live data in seconds, when known. */
    public var liveAgeSeconds: Int?
    /** The feed URL/provider that supplied the live data. */
    public var liveProvider: String?
    /** True when departure/arrival come from a live feed rather than the timetable. */
    public var isRealtime = false
    /** The vehicle's last reported position, when the live feed provides one. */
    public var liveVehicle: TransitVehicle?
    /** The line's resolved identity: official colors, mode and provider, when the planner gave them. */
    public var lineIdentity: TransitLineIdentity?
    public var arrivalPoint: LatLng? { destinationStop ?? path.last }

    /** The line as the operator means it, resolving what the leg carries when no identity was set. */
    public var identity: TransitLineIdentity {
        lineIdentity ?? TransitLineIdentity.resolve(
            shortName: line, headsign: headsign, mode: TransitMode(mode: mode),
            officialColor: color, officialTextColor: textColor,
            provider: liveProvider, agencyID: agencyId, routeID: routeId,
            operatorName: agency, source: .provider, freshness: liveFreshness)
    }
    /** The vehicle kind, kept separate from the broad planner family. */
    public var transitMode: TransitMode { lineIdentity?.mode ?? TransitMode(mode: mode) }
    /** The official line color when one exists, else a neutral color for the mode. */
    public var displayColor: UInt32 { identity.color }
    public var displayTextColor: UInt32 { identity.textColor }
    /** True when the color came from the operator, not from Kite's mode fallback. */
    public var colorIsOfficial: Bool { identity.colorIsOfficial }

    public init(isWalk: Bool, mode: String, line: String = "", color: UInt32? = nil, textColor: UInt32? = nil,
                headsign: String? = nil, fromName: String = "", toName: String = "", depart: Date? = nil,
                arrive: Date? = nil, durationSeconds: Double = 0, distanceMeters: Double = 0, stops: Int = 0,
                delayMinutes: Int? = nil, path: [LatLng] = [], lineIdentity: TransitLineIdentity? = nil) {
        self.isWalk = isWalk; self.mode = mode; self.line = line; self.color = color; self.textColor = textColor
        self.headsign = headsign; self.fromName = fromName; self.toName = toName; self.depart = depart
        self.arrive = arrive; self.durationSeconds = durationSeconds; self.distanceMeters = distanceMeters
        self.stops = stops; self.delayMinutes = delayMinutes; self.path = path
        self.lineIdentity = lineIdentity
    }

    /** What kind of vehicle, for an icon. */
    public var vehicle: Vehicle { Vehicle(mode) }

    public enum Vehicle: Equatable, Sendable {
        case walk, bus, trolleybus, coach, tram, lightRail, metro, train, ferry
        case funicular, cableCar, aerialLift, monorail, bike, other
        init(_ mode: String) {
            switch TransitMode(mode: mode) {
            case .walk: self = .walk
            case .bus: self = .bus
            case .trolleybus: self = .trolleybus
            case .coach: self = .coach
            case .tram: self = .tram
            case .lightRail: self = .lightRail
            case .metro, .subway: self = .metro
            case .suburbanRail, .regionalTrain, .longDistanceTrain, .highSpeedRail: self = .train
            case .ferry: self = .ferry
            case .funicular: self = .funicular
            case .cableCar: self = .cableCar
            case .aerialLift: self = .aerialLift
            case .monorail: self = .monorail
            case .bike: self = .bike
            case .other: self = .other
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

    public init(depart: Date?, arrive: Date?, durationSeconds: Double, transfers: Int, legs: [TransitLeg]) {
        self.depart = depart; self.arrive = arrive; self.durationSeconds = durationSeconds
        self.transfers = transfers; self.legs = legs
    }

    public var hasMetroAccessNodes: Bool { !TransitStationAccess.segments(in: self).isEmpty }
    public var rides: [TransitLeg] { legs.filter { !$0.isWalk } }
    public var walk: [TransitLeg] { legs.filter(\.isWalk) }
    /**
     * A transfer that the live delay is likely to break: the delay on the arriving ride is longer
     * than the walk to the next stop leaves room for. Only a hint — the timetable is still shown.
     */
    public var tightTransfer: Bool {
        for index in legs.indices.dropLast() {
            let ride = legs[index]
            let next = legs[index + 1]
            guard !ride.isWalk, next.isWalk else { continue }
            let delay = max(0, ride.arrivalDelayMinutes ?? ride.delayMinutes ?? 0)
            guard delay > 0 else { continue }
            if next.durationSeconds < Double(delay * 60 + 120) { return true }
        }
        return false
    }
    /** The whole trip is a walk. */
    public var isWalkOnly: Bool { legs.allSatisfy(\.isWalk) }
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
        c.httpAdditionalHeaders = ["User-Agent": "Vela-iOS (https://github.com/matteofx1/vela-ios)"]
        return URLSession(configuration: c)
    }()

    public static func planURL(from: LatLng, to: LatLng, max: Int = 5, time: Date? = nil,
                               arriveBy: Bool = false, widerAccess: Bool = false) -> URL? {
        requestURL(server: base, from: from, to: to, max: max, time: time,
                   arriveBy: arriveBy, widerAccess: widerAccess)
    }

    /// Accept a MOTIS server base URL, optionally behind a reverse proxy path.
    public static func requestURL(server: String, from: LatLng, to: LatLng, max: Int = 5,
                                  time: Date? = nil, arriveBy: Bool = false, widerAccess: Bool = false) -> URL? {
        guard MapLineGeometry.isValid(from), MapLineGeometry.isValid(to),
              var url = URLComponents(string: server.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        if url.path.hasSuffix("/") { url.path.removeLast() }
        url.path += "/api/v2/plan"
        var query = [
            URLQueryItem(name: "fromPlace", value: "\(from.lat.plain),\(from.lng.plain)"),
            URLQueryItem(name: "toPlace", value: "\(to.lat.plain),\(to.lng.plain)"),
            URLQueryItem(name: "numItineraries", value: String(max)),
            URLQueryItem(name: "detailedTransfers", value: "true"),
            URLQueryItem(name: "useRoutedTransfers", value: "true")
        ]
        if let time {
            query.append(URLQueryItem(name: "time", value: ISO8601DateFormatter().string(from: time)))
            if arriveBy { query.append(URLQueryItem(name: "arriveBy", value: "true")) }
        }
        if widerAccess {
            query.append(URLQueryItem(name: "maxPreTransitTime", value: "1800"))
            query.append(URLQueryItem(name: "maxPostTransitTime", value: "1800"))
        }
        url.queryItems = query
        return url.url
    }

    public static func plan(from: LatLng, to: LatLng, time: Date? = nil, arriveBy: Bool = false) async throws -> [TransitTrip] {
        guard let url = planURL(from: from, to: to, time: time, arriveBy: arriveBy) else { return [] }
        let first = try await fetchPlan(url)
        guard first.isEmpty else { return first }
        try Task.checkCancellation()
        guard let expanded = planURL(from: from, to: to, time: time, arriveBy: arriveBy, widerAccess: true) else { return first }
        do {
            return try await fetchPlan(expanded)
        } catch {
            try Task.checkCancellation()
            // An expansion failure doesn't erase the first valid, empty result.
            return first
        }
    }

    public struct PlanResult: Sendable {
        public let trips: [TransitTrip]
        public let provider: String
    }

    /// Use the alternate timetable after a primary outage or an empty primary result.
    public static func planWithFallback(from: LatLng, to: LatLng, time: Date? = nil, arriveBy: Bool = false,
                                        fallbackServer: String) async throws -> PlanResult {
        let fallback = requestURL(server: fallbackServer, from: from, to: to, time: time, arriveBy: arriveBy)
        let primary: [TransitTrip]
        do {
            primary = try await plan(from: from, to: to, time: time, arriveBy: arriveBy)
        } catch {
            try Task.checkCancellation()
            guard let fallback, let host = fallback.host, host != URL(string: base)?.host else { throw error }
            return PlanResult(trips: try await fetchPlan(fallback, provider: host), provider: host)
        }
        try Task.checkCancellation()
        if primary.isEmpty, let fallback, let host = fallback.host, host != URL(string: base)?.host {
            return PlanResult(trips: try await fetchPlan(fallback, provider: host), provider: host)
        }
        return PlanResult(trips: primary, provider: "Transitous")
    }

    private static func fetchPlan(_ url: URL, provider: String = "transitous.org") async throws -> [TransitTrip] {
        let (data, resp) = try await session.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["itineraries"] is [[String: Any]] else { throw URLError(.badServerResponse) }
        return parse(data, provider: provider)
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
        public var track: String?
        public var scheduledTrack: String?
        public var stopCode: String?
        public var isRealtime: Bool = false
        public var routeId: String? = nil
        public var agencyId: String? = nil
        public var vehicle: TransitLeg.Vehicle { TransitLeg.Vehicle(mode) }
        /// The same identity the trip cards and map use, so a line keeps one color everywhere.
        public var identity: TransitLineIdentity {
            TransitLineIdentity.resolve(shortName: line, headsign: headsign, mode: TransitMode(mode: mode),
                                        officialColor: color, officialTextColor: textColor,
                                        provider: "transitous.org", agencyID: agencyId, routeID: routeId,
                                        source: .provider, freshness: isRealtime ? .live : .scheduled)
        }
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
                             time: time, delayMinutes: delay,
                             track: st["track"] as? String ?? place["track"] as? String,
                             scheduledTrack: st["scheduledTrack"] as? String ?? place["scheduledTrack"] as? String,
                             stopCode: st["stopCode"] as? String ?? place["stopCode"] as? String,
                             isRealtime: st["realTime"] as? Bool == true,
                             routeId: st["routeId"] as? String, agencyId: st["agencyId"] as? String)
        }
    }

    /** A stretch of metro, tram, rail or bus line, for the transit map layer. */
    public struct Line: Sendable {
        public var points: [LatLng]
        public var color: UInt32
        public var metro: Bool
        public var names: [String]
        public var mode: TransitMode = .other
        /** Sideways offset in pixels, so lines sharing one track are all visible. */
        public var offset: Double = 0
        /** Stable line identity for a shared track's legend and tests. */
        public var routeKey: String?
    }

    /**
     * Metro, tram, rail and (from close zoom) bus lines in a box, from Transitous' route map.
     * Below zoom 9 the service sends long-distance rail only. A track shared by several lines is
     * returned once per line, with a pixel offset, so the map never pretends it is only the first
     * line's color.
     */
    public static func lines(south: Double, west: Double, north: Double, east: Double, zoom: Int) async -> [Line]? {
        guard let url = URL(string: "\(base)/api/experimental/map/routes?min=\(south),\(west)&max=\(north),\(east)&zoom=\(zoom)"),
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parseLines(data, includeBuses: zoom >= 13)
    }

    public static func parseLines(_ data: Data, includeBuses: Bool = false) -> [Line] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let routes = root["routes"] as? [[String: Any]],
              let polys = root["polylines"] as? [[String: Any]] else { return [] }
        var out: [Line] = []
        for p in polys {
            let rs = (p["routeIndexes"] as? [Int] ?? []).compactMap { routes.indices.contains($0) ? routes[$0] : nil }
            guard let enc = p["polyline"] as? [String: Any], let pts = enc["points"] as? String else { continue }
            let precision = min(7, max(5, (enc["precision"] as? Int) ?? 6))
            let points = Geo.decodePolyline(pts, precision: pow(10, Double(precision)))
            guard points.count >= 2 else { continue }
            // One entry per distinct line on this geometry.
            var seen = Set<String>()
            var lines: [(mode: TransitMode, color: UInt32, name: String, key: String)] = []
            for r in rs {
                let mode = TransitMode(mode: r["mode"] as? String ?? "")
                let shown = mode.isRail || (includeBuses && [.bus, .trolleybus, .coach, .ferry].contains(mode))
                guard shown else { continue }
                let tr = (r["transitRoutes"] as? [[String: Any]])?.first ?? [:]
                let color = hex(tr["color"]) ?? mode.fallbackColor
                let name = (tr["shortName"] as? String) ?? (tr["longName"] as? String) ?? mode.shortLabel
                let key = [mode.rawValue, name, String(color), (tr["routeId"] as? String) ?? ""].joined(separator: "|")
                guard seen.insert(key).inserted else { continue }
                lines.append((mode, color, name, key))
            }
            guard !lines.isEmpty else { continue }
            let n = lines.count
            for (i, line) in lines.enumerated() {
                // Some feeds draw straight chords across missing street shapes, even in
                // polylines with several points. Regional rail and ferries can be much sparser.
                let limit: Double?
                switch line.mode {
                case .tram, .lightRail: limit = 800
                case .bus, .trolleybus: limit = 1_000
                case .metro, .subway, .monorail: limit = 4_000
                default: limit = points.count == 2 && line.mode != .ferry ? 700 : nil
                }
                for segment in MapLineGeometry.segments(points, maximumEdgeMeters: limit) {
                    out.append(Line(points: segment, color: line.color, metro: line.mode == .metro || line.mode == .subway,
                                    names: [line.name], mode: line.mode,
                                    offset: n > 1 ? (Double(i) - Double(n - 1) / 2) * 2.2 : 0,
                                    routeKey: line.key))
                }
            }
        }
        return out
    }

    public static func parse(_ data: Data, provider: String = "transitous.org") -> [TransitTrip] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let its = root["itineraries"] as? [[String: Any]] else { return [] }
        let trips = its.compactMap { itinerary($0, provider: provider) }
        // The planner can repeat a trip; keep the first of each line-up and time.
        var seen = Set<String>()
        return trips.filter { t in
            let key = t.rides.map(\.line).joined(separator: ",") + "\(t.depart?.timeIntervalSince1970 ?? 0)"
            return seen.insert(key).inserted
        }
    }

    private static func itinerary(_ it: [String: Any], provider: String) -> TransitTrip? {
        guard let rawLegs = it["legs"] as? [[String: Any]] else { return nil }
        let legs = rawLegs.map { leg($0, provider: provider) }
        guard legs.contains(where: { !$0.isWalk }) else { return nil } // a walk-only answer isn't transit
        let start = date(it["startTime"]), end = date(it["endTime"])
        let dur = number(it["duration"]) ?? (start.flatMap { s in end.map { $0.timeIntervalSince(s) } } ?? 0)
        let transfers = (it["transfers"] as? Int) ?? max(0, legs.filter { !$0.isWalk }.count - 1)
        return TransitTrip(depart: start, arrive: end, durationSeconds: dur, transfers: transfers, legs: legs)
    }

    private static func leg(_ l: [String: Any], provider: String) -> TransitLeg {
        let mode = l["mode"] as? String ?? ""
        let from = l["from"] as? [String: Any] ?? [:], to = l["to"] as? [String: Any] ?? [:]
        let start = date(l["startTime"]), end = date(l["endTime"])
        let dur = number(l["duration"]) ?? (start.flatMap { s in end.map { $0.timeIntervalSince(s) } } ?? 0)
        var out = TransitLeg(isWalk: TransitLeg.Vehicle(mode) == .walk, mode: mode,
                             fromName: from["name"] as? String ?? "", toName: to["name"] as? String ?? "",
                             depart: start, arrive: end, durationSeconds: dur,
                             distanceMeters: number(l["distance"]) ?? 0, path: path(l))
        out.destinationStop = point(to)
        if (l["legGeometry"] as? [String: Any])?["precision"] == nil,
           let origin = point(from), let destination = out.destinationStop,
           let a = out.path.first, let b = out.path.last,
           (a.distance(to: origin) > 300 || b.distance(to: destination) > 300) {
            let encoded = (l["legGeometry"] as? [String: Any])?["points"] as? String ?? ""
            let alternative = Geo.decodePolyline(encoded, precision: 1e5)
            if let start = alternative.first, let end = alternative.last,
               start.distance(to: origin) < 200, end.distance(to: destination) < 200 {
                out.path = alternative
            } else {
                out.path = [origin, destination]
            }
        }
        if out.path.count < 2, let a = point(from), let b = point(to) { out.path = [a, b] }
        if out.distanceMeters == 0 { out.distanceMeters = Geo.length(out.path) }
        if out.isWalk {
            out.walkSteps = (l["steps"] as? [[String: Any]] ?? []).compactMap(walkStep)
            return out
        }
        out.boardStop = call(from)
        out.exitStop = call(to)
        out.agency = string(l["agencyName"])
        out.serviceNumber = string(l["tripShortName"])
        out.tripId = string(l["tripId"])
        out.routeId = string(l["routeId"])
        out.scheduledDepart = date(l["scheduledStartTime"])
        out.directionId = (l["directionId"] as? NSNumber)?.intValue
            ?? (l["tripDirection"] as? NSNumber)?.intValue
        out.agencyId = string(l["agencyId"])
        out.isRealtime = l["realTime"] as? Bool == true
        if out.isRealtime {
            // The planner's own real-time answer has no separate timestamp here; show it as live
            // until an extra GTFS-Realtime feed refines the freshness.
            out.liveFreshness = .live
            out.liveProvider = provider
        }
        out.serviceAlerts = alerts([l, from, to])
        let intermediate = l["intermediateStops"] as? [[String: Any]] ?? []
        out.intermediateStops = intermediate.compactMap(call)
        out.line = [l["routeShortName"], l["displayName"], l["routeLongName"]]
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        out.color = hex(l["routeColor"])
        out.textColor = hex(l["routeTextColor"])
        out.headsign = string(l["headsign"]) ?? (l["tripTo"] as? [String: Any]).flatMap { string($0["name"]) }
        let routeType = (l["routeType"] as? NSNumber)?.intValue ?? (l["routeType"] as? Int)
        out.lineIdentity = TransitLineIdentity.resolve(
            shortName: out.line, longName: string(l["routeLongName"]), headsign: out.headsign,
            mode: TransitMode(gtfsRouteType: routeType ?? -1) ?? TransitMode(mode: mode),
            routeType: routeType, officialColor: out.color, officialTextColor: out.textColor,
            provider: provider, feedID: string(l["feedId"]) ?? string(l["source"]),
            agencyID: out.agencyId, routeID: out.routeId, operatorName: out.agency,
            source: .provider, freshness: out.liveFreshness)
        out.stops = intermediate.count + 1
        if l["realTime"] as? Bool == true {
            if let start, let scheduled = date(l["scheduledStartTime"]) {
                out.delayMinutes = Int((start.timeIntervalSince(scheduled) / 60).rounded())
            }
            if let end, let scheduled = date(l["scheduledEndTime"]) {
                out.arrivalDelayMinutes = Int((end.timeIntervalSince(scheduled) / 60).rounded())
            }
        }
        return out
    }

    private static func call(_ value: [String: Any]) -> TransitCall? {
        guard let name = string(value["name"]) else { return nil }
        var call = TransitCall(name: name, timeZone: string(value["tz"]), arrival: date(value["arrival"]),
                               departure: date(value["departure"]), track: string(value["track"]) ?? string(value["scheduledTrack"]),
                               scheduledTrack: string(value["scheduledTrack"]), stopCode: string(value["stopCode"]),
                               detail: string(value["description"]), skipped: value["cancelled"] as? Bool == true)
        call.stopId = string(value["stopId"]) ?? string(value["parentId"])
        call.location = point(value)
        return call
    }

    private static func walkStep(_ value: [String: Any]) -> TransitWalkStep? {
        guard let direction = string(value["relativeDirection"]) else { return nil }
        return TransitWalkStep(direction: direction, street: string(value["streetName"]),
                               distance: number(value["distance"]) ?? 0, fromLevel: number(value["fromLevel"]),
                               toLevel: number(value["toLevel"]), fromNode: value["fromOsmNode"] as? Int64,
                               toNode: value["toOsmNode"] as? Int64)
    }

    private static func alerts(_ sources: [[String: Any]]) -> [String] {
        var seen = Set<String>()
        return sources.flatMap { $0["alerts"] as? [[String: Any]] ?? [] }.compactMap { alert in
            let header = string(alert["headerText"])
            let detail = string(alert["descriptionText"])
            let message = [header, detail == header ? nil : detail].compactMap { $0 }.joined(separator: "\n")
            return !message.isEmpty && seen.insert(message).inserted ? message : nil
        }
    }

    private static func string(_ value: Any?) -> String? {
        guard let clean = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !clean.isEmpty else { return nil }
        return clean
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

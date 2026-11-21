import Foundation

/**
 The route being driven, kept in a compact form so an interrupted journey can be resumed with no
 internet. It stores the geometry, the turns and the timing the router returned. Lane pictures,
 roundabout drawings and traffic spans are not stored (they are fetched again when online), and it
 never claims to be able to compute a new route: leaving it offline means keeping on the saved line.
 */
public struct OfflineRouteSnapshot: Codable, Equatable, Sendable {
    public struct Step: Codable, Equatable, Sendable {
        public var type: String
        public var instruction: String
        public var lat: Double
        public var lng: Double
        public var along: Double
        public var length: Double
        public var road: String?
        public var exit: Int?
    }

    public var modeRaw: Int
    /** Latitude, longitude, latitude, longitude… rounded to 1e-6 degrees (about 11 cm). */
    public var coordinates: [Double]
    public var distanceMeters: Double
    public var typicalSeconds: Double
    public var trafficSeconds: Double?
    public var summary: String?
    public var source: String
    public var steps: [Step]

    public init(_ route: Route) {
        modeRaw = route.mode.rawValue
        coordinates = route.polyline.flatMap { [Self.round($0.lat), Self.round($0.lng)] }
        distanceMeters = route.distanceMeters
        typicalSeconds = route.typicalSeconds
        trafficSeconds = route.trafficSeconds
        summary = route.summary
        source = route.source
        steps = route.maneuvers.map {
            Step(type: $0.type.rawValue, instruction: $0.instruction, lat: Self.round($0.location.lat),
                 lng: Self.round($0.location.lng), along: $0.alongMeters, length: $0.distanceMeters,
                 road: $0.road, exit: $0.exit)
        }
    }

    private static func round(_ value: Double) -> Double { (value * 1e6).rounded() / 1e6 }

    /** The route again, with a new identity, or nil when the stored data is not a usable line. */
    public func route() -> Route? {
        guard coordinates.count >= 4, coordinates.count % 2 == 0,
              coordinates.allSatisfy({ $0.isFinite }) else { return nil }
        let line = stride(from: 0, to: coordinates.count, by: 2).map { LatLng(coordinates[$0], coordinates[$0 + 1]) }
        guard line.allSatisfy({ (-90...90).contains($0.lat) && (-180...180).contains($0.lng) }) else { return nil }
        let maneuvers = steps.map {
            Maneuver(type: ManeuverType(rawValue: $0.type) ?? .unknown, instruction: $0.instruction,
                     location: LatLng($0.lat, $0.lng), alongMeters: $0.along, distanceMeters: $0.length,
                     road: $0.road, exit: $0.exit)
        }
        return Route(mode: TravelMode(rawValue: modeRaw) ?? .drive, polyline: line, distanceMeters: distanceMeters,
                     typicalSeconds: typicalSeconds, trafficSeconds: trafficSeconds, summary: summary,
                     maneuvers: maneuvers, source: source + "+saved")
    }
}

/** An interrupted journey: where it was going and the route it was on. */
public struct OfflineJourney: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var savedAt: Date
    public var destination: Place
    public var stops: [Place]
    public var avoidTolls: Bool
    public var avoidHighways: Bool
    public var route: OfflineRouteSnapshot

    public init(destination: Place, stops: [Place], avoidTolls: Bool, avoidHighways: Bool,
                route: Route, savedAt: Date = Date()) {
        schemaVersion = Self.currentSchemaVersion
        self.savedAt = savedAt
        self.destination = destination
        self.stops = stops
        self.avoidTolls = avoidTolls
        self.avoidHighways = avoidHighways
        self.route = OfflineRouteSnapshot(route)
    }

    /** Older than this, the plan is stale and a fresh route is worth asking for. */
    public static let lifetime: TimeInterval = 2 * 3600

    public func isFresh(now: Date = Date()) -> Bool {
        now.timeIntervalSince(savedAt) < Self.lifetime && now >= savedAt.addingTimeInterval(-60)
    }
}

/** One journey in one file; writing is atomic, so a crash while saving leaves the previous copy intact. */
public final class OfflineJourneyStore: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()

    public init(url: URL) { self.url = url }

    public static func standard() -> OfflineJourneyStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return OfflineJourneyStore(url: base.appendingPathComponent("kite-interrupted-journey.json"))
    }

    @discardableResult
    public func save(_ journey: OfflineJourney) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? JSONEncoder().encode(journey) else { return false }
        do { try data.write(to: url, options: .atomic); return true } catch { return false }
    }

    public func load(now: Date = Date()) -> OfflineJourney? {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url),
              let journey = try? JSONDecoder().decode(OfflineJourney.self, from: data),
              journey.schemaVersion <= OfflineJourney.currentSchemaVersion,
              journey.isFresh(now: now), journey.route.route() != nil else { return nil }
        return journey
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: url)
    }
}

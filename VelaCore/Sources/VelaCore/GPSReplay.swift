import Foundation

/**
 A recorded or generated drive that can be played back as GPS fixes, to reproduce a roundabout, a GPS
 fault or a slow reroute without leaving the desk. Positions are `east`/`north` metres from the fixture's
 own `origin`, so a fixture shared as a bug report says where the road bends, not where it is on Earth.
 */
public struct GPSReplayFixture: Codable, Equatable, Sendable {
    public static let schema = "kite-gps-replay-v1"

    public struct Fix: Codable, Equatable, Sendable {
        /** Seconds from the start of the drive. */
        public var t: Double
        public var east: Double
        public var north: Double
        public var accuracy: Double
        /** Metres per second; negative when unknown, as CoreLocation reports it. */
        public var speed: Double
        /** Degrees from north; negative when unknown. */
        public var course: Double

        public init(t: Double, east: Double, north: Double, accuracy: Double = 5, speed: Double = -1, course: Double = -1) {
            self.t = t; self.east = east; self.north = north
            self.accuracy = accuracy; self.speed = speed; self.course = course
        }
    }

    public var schema: String
    public var name: String
    public var notes: String
    /** Where `east = north = 0` is. A shared fixture may use any point. */
    public var origin: LatLng
    public var fixes: [Fix]
    /** Geometry the fixes were recorded on, so a fixture is self-contained and testable. */
    public var routePolyline: [LatLng]?

    public init(name: String, notes: String = "", origin: LatLng, fixes: [Fix], routePolyline: [LatLng]? = nil) {
        schema = Self.schema
        self.name = name
        self.notes = notes
        self.origin = origin
        self.fixes = fixes
        self.routePolyline = routePolyline
    }

    public func coordinate(of fix: Fix) -> LatLng {
        LatLng(origin.lat + fix.north / 110_540,
               origin.lng + fix.east / (111_320 * max(0.01, cos(origin.lat * .pi / 180))))
    }

    public var duration: Double { fixes.last?.t ?? 0 }

    public static func decode(_ data: Data) -> GPSReplayFixture? {
        guard data.count <= 5_000_000,
              let fixture = try? JSONDecoder().decode(GPSReplayFixture.self, from: data),
              fixture.schema == Self.schema,
              fixture.fixes.count >= 2,
              fixture.fixes.allSatisfy({ $0.t.isFinite && $0.east.isFinite && $0.north.isFinite }),
              zip(fixture.fixes, fixture.fixes.dropFirst()).allSatisfy({ $0.t <= $1.t })
        else { return nil }
        return fixture
    }

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }

    /** A steady drive along [line]: one fix every [interval] seconds at [speed] m/s. */
    public static func drive(along line: [LatLng], speed: Double, interval: Double = 1, accuracy: Double = 5,
                             name: String = "Generated drive") -> GPSReplayFixture {
        guard let origin = line.first, line.count >= 2, speed > 0, interval > 0 else {
            return GPSReplayFixture(name: name, origin: line.first ?? LatLng(0, 0), fixes: [])
        }
        let cumulative = Geo.cumulative(line)
        let total = cumulative.last ?? 0
        var fixes: [Fix] = []
        var t = 0.0
        while true {
            let along = min(total, t * speed)
            let point = Geo.point(along: line, meters: along, cumulative: cumulative)
            let ahead = Geo.point(along: line, meters: min(total, along + 5), cumulative: cumulative)
            let local = DiagnosticRedactor.offset(of: point, from: origin)
            let course = point.distance(to: ahead) > 0.5 ? Geo.bearing(point, ahead) : (fixes.last?.course ?? -1)
            fixes.append(Fix(t: t, east: local.east, north: local.north, accuracy: accuracy,
                             speed: along >= total ? 0 : speed, course: course))
            if along >= total { break }
            t += interval
        }
        return GPSReplayFixture(name: name, origin: origin, fixes: fixes)
    }
}

/** Faults that can be laid over a clean drive. Everything is deterministic for a given seed. */
public struct GPSReplayOptions: Sendable {
    /** Standard deviation of the position error in metres (0 = clean). */
    public var noiseMeters = 0.0
    /** No fixes at all in these time ranges (a tunnel, an urban canyon). */
    public var dropouts: [ClosedRange<Double>] = []
    /** Fixes in these ranges arrive late by `lateBySeconds` but keep their original timestamp. */
    public var lateRanges: [ClosedRange<Double>] = []
    public var lateBySeconds = 0.0
    /** Fixes in these ranges report this (poor) accuracy and a position jump of `jumpMeters`. */
    public var poorRanges: [ClosedRange<Double>] = []
    public var poorAccuracy = 150.0
    public var jumpMeters = 80.0
    public var seed: UInt64 = 1

    public init() {}
}

/** One fix to deliver: when to deliver it (`deliverAt`) and what it says (`fix`, stamped `fix.t`). */
public struct ScheduledReplayFix: Equatable, Sendable {
    public var deliverAt: Double
    public var fix: GPSReplayFixture.Fix
    public var coordinate: LatLng
    public var isLate: Bool
}

public enum GPSReplayPlan {
    /** The delivery schedule, ordered by delivery time (a late fix can arrive after a newer one). */
    public static func schedule(_ fixture: GPSReplayFixture, options: GPSReplayOptions = GPSReplayOptions()) -> [ScheduledReplayFix] {
        var random = SplitMix(seed: options.seed)
        var out: [ScheduledReplayFix] = []
        for original in fixture.fixes {
            if options.dropouts.contains(where: { $0.contains(original.t) }) { continue }
            var fix = original
            if options.noiseMeters > 0 {
                fix.east += random.gaussian() * options.noiseMeters
                fix.north += random.gaussian() * options.noiseMeters
                fix.accuracy = max(fix.accuracy, options.noiseMeters * 1.5)
            }
            if options.poorRanges.contains(where: { $0.contains(original.t) }) {
                let angle = random.unit() * 2 * .pi
                fix.east += cos(angle) * options.jumpMeters
                fix.north += sin(angle) * options.jumpMeters
                fix.accuracy = options.poorAccuracy
                fix.course = -1
            }
            let late = options.lateRanges.contains(where: { $0.contains(original.t) })
            out.append(ScheduledReplayFix(deliverAt: original.t + (late ? options.lateBySeconds : 0), fix: fix,
                                          coordinate: fixture.coordinate(of: fix), isLate: late))
        }
        return out.enumerated().sorted { a, b in
            a.element.deliverAt != b.element.deliverAt ? a.element.deliverAt < b.element.deliverAt : a.offset < b.offset
        }.map(\.element)
    }
}

/** Small deterministic generator, so a replay is the same on every run and every machine. */
struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    mutating func gaussian() -> Double {
        let u1 = max(unit(), 1e-12), u2 = unit()
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}

/// One explicitly selected incident. It contains real locations, so it requires separate consent.
public struct NavigationReplayIncident: Codable, Sendable {
    public struct Observation: Codable, Sendable, Equatable {
        public let instruction: String
        public let roundaboutExit: Int?
        public let trafficLights: Int
        public let offRoute: Bool

        public init(instruction: String, roundaboutExit: Int?, trafficLights: Int, offRoute: Bool) {
            self.instruction = instruction
            self.roundaboutExit = roundaboutExit
            self.trafficLights = trafficLights
            self.offRoute = offRoute
        }
    }

    public struct Signal: Codable, Sendable {
        public let location: LatLng
        public let alongMeters: Double
        public let directionCertain: Bool
        public let ambiguous: Bool

        public init(location: LatLng, alongMeters: Double, directionCertain: Bool, ambiguous: Bool) {
            self.location = location
            self.alongMeters = alongMeters
            self.directionCertain = directionCertain
            self.ambiguous = ambiguous
        }
    }

    public static let currentSchema = "kite-navigation-incident-v1"
    public let schema: String
    public var route: OfflineRouteSnapshot
    public var gps: GPSReplayFixture
    public var signalCandidates: [Signal]
    public var observed: Observation
    public var expectedRoundaboutExit: Int?
    public var expectedTrafficLights: Int?

    private enum CodingKeys: String, CodingKey {
        case schema, route, gps, signalCandidates, observed, expectedRoundaboutExit, expectedTrafficLights
    }

    public init(route: OfflineRouteSnapshot, gps: GPSReplayFixture, signalCandidates: [Signal], observed: Observation,
                expectedRoundaboutExit: Int? = nil, expectedTrafficLights: Int? = nil) {
        self.schema = Self.currentSchema
        self.route = route
        self.gps = gps
        self.signalCandidates = signalCandidates
        self.observed = observed
        self.expectedRoundaboutExit = expectedRoundaboutExit
        self.expectedTrafficLights = expectedTrafficLights
    }

    public static func decode(_ data: Data) -> Self? {
        guard data.count <= 2_000_000,
              let value = try? JSONDecoder().decode(Self.self, from: data),
              value.schema == Self.currentSchema,
              value.route.coordinates.count <= 20_000,
              value.signalCandidates.count <= 100,
              value.signalCandidates.allSatisfy({
                  (0...10_000).contains($0.alongMeters) &&
                  (-90...90).contains($0.location.lat) && (-180...180).contains($0.location.lng)
              }),
              value.gps.schema == GPSReplayFixture.schema,
              (2...180).contains(value.gps.fixes.count),
              (0...90).contains(value.gps.duration), value.gps.routePolyline == nil,
              value.gps.fixes.allSatisfy({
                  (0...90).contains($0.t) && (0...1_000).contains($0.accuracy) &&
                  (-1...150).contains($0.speed) && (-1...360).contains($0.course) &&
                  abs($0.east) <= 20_000 && abs($0.north) <= 20_000
              }),
              zip(value.gps.fixes, value.gps.fixes.dropFirst()).allSatisfy({ $0.t < $1.t }),
              (-85...85).contains(value.gps.origin.lat), (-180...180).contains(value.gps.origin.lng),
              value.gps.fixes.allSatisfy({
                  let point = value.gps.coordinate(of: $0)
                  return (-85...85).contains(point.lat) && (-180...180).contains(point.lng)
              }),
              value.route.route() != nil else { return nil }
        return value
    }

    public func replay() -> Observation? {
        guard let route = route.route() else { return nil }
        let tracker = RouteTracker(route: route)
        var progress: RouteTracker.Progress?
        for step in GPSReplayPlan.schedule(gps) {
            // Match the app's navigation fix gate. The captured outlier remains in the fixture.
            guard step.fix.accuracy <= (route.mode == .drive ? 60 : 40) else { continue }
            progress = tracker.update(step.coordinate, accuracy: max(5, step.fix.accuracy),
                                      heading: step.fix.course >= 0 && step.fix.speed >= 4 ? step.fix.course : nil,
                                      speed: max(0, step.fix.speed), now: Date(timeIntervalSince1970: step.fix.t))
        }
        guard let progress else { return nil }
        let maneuver = progress.nextIndex.flatMap {
            route.maneuvers.indices.contains($0) ? route.maneuvers[$0] : nil
        } ?? route.maneuvers.first
        let signals = signalCandidates.filter {
            Self.isUpcomingSignal(along: $0.alongMeters, traveled: progress.alongMeters, mode: route.mode,
                                  certain: $0.directionCertain, ambiguous: $0.ambiguous)
        }.prefix(6).count
        return Observation(instruction: maneuver?.instruction ?? "", roundaboutExit: maneuver?.exit,
                           trafficLights: signals, offRoute: progress.offRoute)
    }

    public static func isUpcomingSignal(along: Double, traveled: Double, mode: TravelMode,
                                        certain: Bool, ambiguous: Bool) -> Bool {
        along >= traveled && (mode != .drive || (certain && !ambiguous))
    }
}

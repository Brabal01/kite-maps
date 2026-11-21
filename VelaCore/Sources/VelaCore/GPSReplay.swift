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

    public init(name: String, notes: String = "", origin: LatLng, fixes: [Fix]) {
        schema = Self.schema
        self.name = name
        self.notes = notes
        self.origin = origin
        self.fixes = fixes
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

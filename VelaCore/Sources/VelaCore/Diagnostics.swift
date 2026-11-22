import Foundation

/**
 An in-memory, short-lived diagnostic trail that never needs a precise position.

 * Ordinary events carry only route-relative and technical values (distance
   along the route, offset, accuracy, speed, state names). They are always
   safe to share.
 * Positions are recorded only while the user has switched detailed
   diagnostics on, and only as latitude/longitude held in memory. A report
   never contains them as coordinates: they are exported as metres east/north
   of the first recorded point, so a roundabout or GPS fault can be replayed
   anywhere without revealing where it happened.
 * Everything is kept in memory only, for at most `retention`, and at most
   `capacity` events; nothing is written to disk and a restart clears it.
 */
public final class DiagnosticsLog: @unchecked Sendable {
    public static let shared = DiagnosticsLog()

    public struct Event: Sendable, Equatable {
        public var time: Date
        public var kind: String
        /** Technical values only; passed through `DiagnosticRedactor` on export. */
        public var fields: [String: String]
        public var position: LatLng?
    }

    public let retention: TimeInterval
    public let capacity: Int
    private let lock = NSLock()
    private var events: [Event] = []
    private var detailed = false

    public init(retention: TimeInterval = 3 * 3600, capacity: Int = 800) {
        self.retention = retention
        self.capacity = capacity
    }

    public var isDetailed: Bool {
        lock.lock(); defer { lock.unlock() }
        return detailed
    }

    /** Turning detailed mode off also forgets every recorded position. */
    public func setDetailed(_ on: Bool) {
        lock.lock(); defer { lock.unlock() }
        detailed = on
        if !on { events = events.map { var e = $0; e.position = nil; return e } }
    }

    /** [position] is kept only in detailed mode. */
    public func record(_ kind: String, _ fields: [String: String] = [:], position: LatLng? = nil, at time: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        events.append(Event(time: time, kind: kind, fields: fields, position: detailed ? position : nil))
        prune(now: time)
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        events = []
    }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return events.count
    }

    public func snapshot(now: Date = Date()) -> [Event] {
        lock.lock(); defer { lock.unlock() }
        prune(now: now)
        return events
    }

    private func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-retention)
        if let first = events.firstIndex(where: { $0.time >= cutoff }), first > 0 { events.removeFirst(first) }
        else if events.allSatisfy({ $0.time < cutoff }) { events = [] }
        if events.count > capacity { events.removeFirst(events.count - capacity) }
    }

    /** Three distinct exports, so a user never shares more than they understood. */
    public enum ReportLevel: String, CaseIterable, Sendable {
        case technical
        case pseudonymized
        case replay

        public var title: String {
            switch self {
            case .technical: return "Technical only"
            case .pseudonymized: return "Coarse movement shape"
            case .replay: return "Detailed GPS replay"
            }
        }

        public var explanation: String {
            switch self {
            case .technical: return "Distances, GPS accuracy, speed and navigation states. No movement at all."
            case .pseudonymized: return "Movement snapped to a 500 m grid and times rounded to 15 s. Still potentially identifying if someone knows where you started."
            case .replay: return "Full relative movement, enough to replay a roundabout or GPS fault. Potentially identifying: only share after explicit consent."
            }
        }
    }

    /**
     * A shareable report. No level ever contains coordinates, addresses or place names; only the
     * replay level contains a full relative trace, and it must be chosen explicitly in the UI.
     */
    public func report(appVersion: String, level: ReportLevel, now: Date = Date()) -> Data {
        let allowedFields: [String: Set<String>] = [
            "fix": ["along", "off", "next", "toNext", "offRoute", "acc", "speed", "evidence"],
            "reroute": ["heading", "acc"],
            "newRoute": ["meters", "steps"]
        ]
        let events = snapshot(now: now).filter { allowedFields[$0.kind] != nil }
        let start = events.first?.time ?? now
        let anchor = events.compactMap(\.position).first
        let rows: [[String: Any]] = events.map { event in
            var row: [String: Any] = [
                "t": (event.time.timeIntervalSince(start) * 10).rounded() / 10,
                "kind": DiagnosticRedactor.sanitize(event.kind),
            ]
            let fields = event.fields.filter { key, value in
                guard allowedFields[event.kind]?.contains(key) == true else { return false }
                return value == "true" || value == "false" || (Double(value)?.isFinite ?? false)
            }
            if !fields.isEmpty { row["fields"] = fields }
            if level != .technical, let at = event.position, let anchor {
                let local = DiagnosticRedactor.offset(of: at, from: anchor)
                let grid = level == .pseudonymized ? 500.0 : 1.0
                row["east"] = DiagnosticRedactor.snap(local.east, to: grid)
                row["north"] = DiagnosticRedactor.snap(local.north, to: grid)
                if level == .pseudonymized { row["t"] = DiagnosticRedactor.snap(event.time.timeIntervalSince(start), to: 15) }
            }
            return row
        }
        let document: [String: Any] = [
            "schema": "kite-diagnostics-v1",
            "app": DiagnosticRedactor.sanitize(appVersion),
            "durationSeconds": Int(events.last.map { $0.time.timeIntervalSince(start) } ?? 0),
            "level": level.rawValue,
            "containsTrack": level != .technical && anchor != nil,
            "note": level == .technical
                ? "No coordinates, movement, addresses or place names."
                : "No absolute coordinates. Movement is relative to an unknown start and may still identify you when a starting point is known.",
            "events": rows,
        ]
        return (try? JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }
}

public enum DiagnosticRedactor {
    /** Coordinates written as decimals with three or more places, as in `50.08804,14.42076`. */
    private static let coordinate = try! NSRegularExpression(pattern: #"-?\d{1,3}\.\d{3,}"#)
    private static let email = try! NSRegularExpression(pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#)

    /** Removes anything coordinate- or e-mail-shaped and caps the length. */
    public static func sanitize(_ text: String, limit: Int = 120) -> String {
        var result = String(text.prefix(limit))
        for (pattern, replacement) in [(coordinate, "<number>"), (email, "<email>")] {
            result = pattern.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result),
                                                      withTemplate: replacement)
        }
        return result
    }

    /** Metres east and north of [origin], on a local flat approximation (fine for a few kilometres). */
    public static func offset(of point: LatLng, from origin: LatLng) -> (east: Double, north: Double) {
        let north = (point.lat - origin.lat) * 110_540
        let east = (point.lng - origin.lng) * 111_320 * cos(origin.lat * .pi / 180)
        return (east, north)
    }

    public static func snap(_ value: Double, to grid: Double) -> Double {
        guard grid > 0, value.isFinite else { return value }
        return (value / grid).rounded() * grid
    }

    /** A position rounded to about 1 km, for UI that wants "roughly where" without a precise location. */
    public static func coarse(_ point: LatLng) -> String {
        String(format: "%.2f,%.2f", locale: Locale(identifier: "en_US_POSIX"), point.lat, point.lng)
    }
}

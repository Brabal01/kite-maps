import Foundation

/** What kind of road event is competing for the one large driving card. */
public enum AlertKind: String, Equatable, Sendable {
    case camera, police, accident, hazard, closure, traffic
    case averageCheck, aircraft, roadControl, speedLimit
}

public enum AlertSeverity: Int, Comparable, Sendable {
    case info = 0, notice = 1, warning = 2, critical = 3

    public static func < (lhs: AlertSeverity, rhs: AlertSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/**
 Everything the coordinator needs to know about one event. The app maps its
 camera/Waze/control/provider objects into this shape; the coordinator never
 talks to the network or the map.
 */
public struct AlertCandidate: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: AlertKind
    public var source: String
    public var severity: AlertSeverity
    public var title: String
    /// Meters along the selected route, when it is a route event.
    public var alongMeters: Double?
    /// Straight-line or route distance to the event, whichever the caller trusts.
    public var distanceMeters: Double
    /// Direction of the event in degrees (the way its camera/road faces), when known.
    public var eventBearing: Double?
    /// The direction the driver is travelling at that point, when known.
    public var routeBearing: Double?
    public var accuracyMeters: Double
    /// 0…1: provider confidence, or a derived confidence when the provider has no score.
    public var confidence: Double
    public var reportedAt: Date
    public var expiresAt: Date?
    public var speedLimitKmh: Double?
    public var vehicleSpeedKmh: Double?
    public var isReply: Bool

    public init(id: String, kind: AlertKind, source: String, severity: AlertSeverity,
                title: String, distanceMeters: Double, alongMeters: Double? = nil,
                eventBearing: Double? = nil, routeBearing: Double? = nil,
                accuracyMeters: Double = 20, confidence: Double = 1,
                reportedAt: Date = Date(), expiresAt: Date? = nil,
                speedLimitKmh: Double? = nil, vehicleSpeedKmh: Double? = nil,
                isReply: Bool = false) {
        self.id = id
        self.kind = kind
        self.source = source
        self.severity = severity
        self.title = title
        self.distanceMeters = distanceMeters
        self.alongMeters = alongMeters
        self.eventBearing = eventBearing
        self.routeBearing = routeBearing
        self.accuracyMeters = accuracyMeters
        self.confidence = confidence
        self.reportedAt = reportedAt
        self.expiresAt = expiresAt
        self.speedLimitKmh = speedLimitKmh
        self.vehicleSpeedKmh = vehicleSpeedKmh
        self.isReply = isReply
    }

    public var isOverLimit: Bool {
        guard let limit = speedLimitKmh, let speed = vehicleSpeedKmh else { return false }
        return speed > limit + 3
    }

    /** Opposite carriageways and cross streets are not our warning. */
    public func isRelevant(now: Date) -> Bool {
        if isReply { return false }
        if let expiresAt, expiresAt <= now { return false }
        if !distanceMeters.isFinite || distanceMeters < 0 { return false }
        if !confidence.isFinite || confidence < 0.2 { return false }
        guard let eventBearing, let routeBearing,
              eventBearing.isFinite, routeBearing.isFinite else { return true }
        let raw = abs(eventBearing - routeBearing).truncatingRemainder(dividingBy: 360)
        let difference = min(raw, 360 - raw)
        return difference <= 65
    }

    /** Higher is more urgent. Distance and freshness matter, but a camera over the limit is special. */
    public func score(now: Date) -> Double {
        var value = Double(severity.rawValue) * 100
        value += max(0, 140 - min(distanceMeters, 140)) * 0.9
        value += max(0, 1 - min(1, max(0, now.timeIntervalSince(reportedAt)) / 3_600)) * 18
        value += confidence * 20
        switch kind {
        case .camera:
            if isOverLimit { value += 120 }
        case .closure, .accident:
            value += 28
        case .traffic:
            value += 10
        case .aircraft, .averageCheck:
            value -= 18
        case .police, .hazard, .roadControl, .speedLimit:
            break
        }
        if let limit = speedLimitKmh, let speed = vehicleSpeedKmh, speed > limit {
            value += min(30, speed - limit)
        }
        return value
    }
}

public struct AlertPresentation: Equatable, Sendable {
    public var primary: AlertCandidate?
    public var queued: [AlertCandidate]
    public var suppressedIDs: [String]

    public init(primary: AlertCandidate? = nil, queued: [AlertCandidate] = [],
                suppressedIDs: [String] = []) {
        self.primary = primary
        self.queued = queued
        self.suppressedIDs = suppressedIDs
    }
}

/**
 One place decides which warning gets the card.

 Hysteresis stops two nearly equal warnings from swapping every frame; a
 cooldown stops a dismissed report from returning immediately; and an urgent
 maneuver suppresses lower-priority cards so "Turn right" is never covered by
 a stale hazard.
 */
public struct AlertCoordinator: Equatable, Sendable {
    public var cooldown: TimeInterval
    public var hysteresis: Double
    public var maxQueue: Int
    public var minimumSeverity: AlertSeverity
    private var currentPrimaryID: String?
    private var suppressedUntil: [String: Date] = [:]

    public init(cooldown: TimeInterval = 20, hysteresis: Double = 0.18,
                maxQueue: Int = 3, minimumSeverity: AlertSeverity = .info) {
        self.cooldown = cooldown
        self.hysteresis = hysteresis
        self.maxQueue = maxQueue
        self.minimumSeverity = minimumSeverity
    }

    public mutating func update(_ candidates: [AlertCandidate], now: Date = Date(),
                                maneuverUrgent: Bool = false) -> AlertPresentation {
        suppressedUntil = suppressedUntil.filter { $0.value > now }
        var relevant = candidates.filter {
            $0.severity >= minimumSeverity && $0.isRelevant(now: now) &&
            suppressedUntil[$0.id] == nil
        }
        if maneuverUrgent {
            relevant = relevant.filter { $0.severity == .critical || ($0.kind == .camera && $0.isOverLimit) }
        }

        // Two providers can describe one crash or camera. Keep the strongest and freshest.
        var deduped: [String: AlertCandidate] = [:]
        for candidate in relevant {
            let key = dedupeKey(candidate)
            if let existing = deduped[key] {
                let oldScore = existing.score(now: now)
                let newScore = candidate.score(now: now)
                if newScore > oldScore { deduped[key] = candidate }
            } else {
                deduped[key] = candidate
            }
        }
        let ranked = deduped.values.sorted {
            let a = $0.score(now: now), b = $1.score(now: now)
            if a == b { return $0.distanceMeters < $1.distanceMeters }
            return a > b
        }
        guard let best = ranked.first else {
            currentPrimaryID = nil
            return AlertPresentation()
        }

        var primary = best
        let current = currentPrimaryID.flatMap { id in ranked.first { $0.id == id } }
        if let current, best.kind == .camera, best.isOverLimit,
           !(current.kind == .camera && current.isOverLimit) {
            // A camera while over the limit always takes the card; it is the one that costs a fine.
            primary = best
        } else if let current,
                  current.score(now: now) >= best.score(now: now) * (1 - hysteresis) {
            // Keep the current card unless the challenger is clearly more urgent.
            primary = current
        }
        currentPrimaryID = primary.id
        let queued = ranked.filter { $0.id != primary.id }.prefix(maxQueue).map { $0 }
        return AlertPresentation(primary: primary, queued: Array(queued),
                                 suppressedIDs: Array(suppressedUntil.keys))
    }

    /** The user hid the card: don't bring the same report back immediately. */
    public mutating func dismiss(_ id: String, now: Date = Date()) {
        suppressedUntil[id] = now.addingTimeInterval(cooldown)
        if currentPrimaryID == id { currentPrimaryID = nil }
    }

    /// Bearing only, so an event with a camera direction is not copied as a second card.
    private func dedupeKey(_ c: AlertCandidate) -> String {
        if c.kind == .camera || c.kind == .roadControl {
            return "\(c.kind.rawValue)|\(c.alongMeters.map { Int($0 / 25) } ?? -1)"
        }
        return "\(c.kind.rawValue)|\(Int(c.distanceMeters / 30))"
    }
}

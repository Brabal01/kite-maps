import Foundation

/// Recognizes boarding only after a visit to the stop and sustained movement along the booked leg.
public struct TransitBoarding {
    private let stop: LatLng
    private let path: [LatLng]
    private let cumulative: [Double]
    private var lastFix: Date?
    private var seenAtStop: Date?
    private var movement: (time: Date, along: Double)?

    public init(path: [LatLng], stop: LatLng) {
        self.stop = stop
        self.path = Geo.slice(path, from: 0, to: min(900, Geo.length(path)))
        cumulative = Geo.cumulative(self.path)
    }

    public mutating func observe(_ point: LatLng, accuracy: Double, speed: Double, course: Double,
                                 at time: Date, departure: Date?) -> Bool {
        guard lastFix.map({ time > $0 }) ?? true else { return false }
        lastFix = time
        guard path.count >= 2, (0...45).contains(accuracy) else {
            movement = nil
            return false
        }
        if point.distance(to: stop) <= 68 { seenAtStop = time }
        guard let seenAtStop, time.timeIntervalSince(seenAtStop) <= 210,
              departure.map({ (-90...360).contains(time.timeIntervalSince($0)) }) ?? true else {
            movement = nil
            return false
        }
        let projected = Geo.project(point, on: path, cumulative: cumulative)
        guard projected.offset <= 35, (85...850).contains(projected.along), speed.isFinite, speed >= 2.8 else {
            movement = nil
            return false
        }
        if course >= 0 {
            let before = Geo.point(along: path, meters: projected.along - 12, cumulative: cumulative)
            let after = Geo.point(along: path, meters: projected.along + 12, cumulative: cumulative)
            guard abs(NavigationCamera.shortestTurn(from: course, to: Geo.bearing(before, after))) <= 60 else {
                movement = nil
                return false
            }
        }
        guard let movement, time.timeIntervalSince(movement.time) <= 20,
              projected.along >= movement.along - 12 else {
            self.movement = (time, projected.along)
            return false
        }
        return time.timeIntervalSince(movement.time) >= 0.9 && projected.along - movement.along >= 24
    }
}

/// Keeps GPS-confirmed stop order separate from estimates based on the timetable.
public struct TransitRide {
    private let path: [LatLng]
    private let locations: [LatLng]
    private let cumulative: [Double]
    private let anchors: [Double]
    private var lastFix: Date?
    private var lastAlong = 0.0
    private var closeFixes = 0
    public private(set) var nextIndex = 1
    public private(set) var lastPositionAt: Date?

    public struct Update {
        public let exitApproach: Bool
        public let readyToExit: Bool
    }

    public init(leg: TransitLeg) {
        let path = leg.path
        let locations = leg.calls.map(\.location)
        let cumulative = Geo.cumulative(path)
        let end = cumulative.last ?? 0
        var start = 0.0
        self.path = path
        self.locations = locations
        self.cumulative = cumulative
        anchors = locations.enumerated().map { index, location in
            if index == locations.count - 1, let last = path.last, last.distance(to: location) < 130 {
                return end
            }
            let remaining = Geo.slice(path, from: start, to: end, cumulative: cumulative)
            if remaining.count > 1 { start += Geo.project(location, on: remaining).along }
            return start
        }
    }

    /// Returns nil if GPS provided no usable evidence. The published stop then stays unchanged.
    public mutating func observe(_ point: LatLng, accuracy: Double, speed: Double, at time: Date) -> Update? {
        guard lastFix.map({ time > $0 }) ?? true else { return nil }
        lastFix = time
        guard (0...75).contains(accuracy), let exit = locations.last, locations.indices.contains(nextIndex) else {
            closeFixes = 0
            return nil
        }

        let floor = max(0, lastAlong - 140)
        let seconds = lastPositionAt.map { time.timeIntervalSince($0) } ?? 45
        let ceiling = min(cumulative.last ?? 0, lastAlong + max(4200, seconds * 115))
        let window = Geo.slice(path, from: floor, to: ceiling, cumulative: cumulative)
        let projected = window.count > 1 ? Geo.project(point, on: window) : nil
        guard projected.map({ $0.offset <= 125 }) ?? true else {
            closeFixes = 0
            return nil
        }

        let current = projected.map { floor + $0.along }
        lastPositionAt = time
        if let current { lastAlong = max(lastAlong, current) }
        while nextIndex < locations.count - 1 {
            let anchor = anchors[nextIndex]
            let reached = point.distance(to: locations[nextIndex]) < 75 && (current.map { $0 >= anchor - 100 } ?? true)
            let passed = current.map { $0 > anchor + 65 } ?? false
            guard reached || passed else { break }
            nextIndex += 1
        }
        let distance = point.distance(to: exit)
        let finalIsNext = nextIndex == locations.count - 1
        let nearExit = finalIsNext && distance < 65 && (current.map { $0 >= anchors[nextIndex] - 110 } ?? true)
        closeFixes = nearExit ? closeFixes + 1 : 0
        return Update(exitApproach: finalIsNext && distance < 180,
                      readyToExit: closeFixes >= 2 && speed < 4)
    }

    public func scheduledNext(in calls: [TransitCall], at time: Date) -> TransitCall? {
        let remaining = calls.dropFirst(nextIndex).filter { !$0.cancelled }
        return remaining.first { ($0.departure ?? $0.arrival).map { $0 >= time } ?? true } ?? remaining.last
    }
}

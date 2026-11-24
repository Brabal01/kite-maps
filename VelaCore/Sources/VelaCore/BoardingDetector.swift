import Foundation

/**
 Decides, from movement alone, whether the user has really boarded the ride they planned, so the
 "Get off at…" guidance can start without a tap. A wrong guess is worse than no guess (it would hide
 the boarding prompt for a vehicle never entered), so the detector wants all of this at once:

 * the user was seen waiting (slowly) at the boarding stop shortly before or after the departure time;
 * after departure they move faster than walking, steadily, for several fixes in a row;
 * they have travelled at least `minimumAlongMeters` along the ride's own line, never going backwards,
   staying close to it and heading the way the line goes;
 * and, when the live vehicle's position is known, they are within `vehicleRadius` of it.

 Anything weaker leaves the manual "I'm on board" button as the only way. A person in a car driving
 beside the tram line fails the "seen at the stop" test, which is the point.
 */
public struct BoardingDetector: Sendable {
    public struct Sample: Sendable {
        public var time: Date
        public var location: LatLng
        public var accuracy: Double
        public var speed: Double
        public var course: Double
        public init(time: Date, location: LatLng, accuracy: Double, speed: Double, course: Double) {
            self.time = time; self.location = location; self.accuracy = accuracy
            self.speed = speed; self.course = course
        }
    }

    public enum Decision: Equatable, Sendable {
        case notYet
        case boarded
    }

    public var minimumAlongMeters = 120.0
    public var maximumOffsetMeters = 40.0
    public var minimumSpeed = 4.0
    public var requiredFixes = 4
    public var stopRadius = 80.0
    public var vehicleRadius = 120.0

    private var sawAtStop = false
    private var fastFixes = 0
    private var lastAlong: Double?
    private var startAlong: Double?

    public init() {}

    /// Standing or strolling at the stop. A vehicle passing the stop at speed is not someone waiting for the ride.
    private func waitingAtStop(_ sample: Sample, _ stop: LatLng) -> Bool {
        sample.location.distance(to: stop) <= stopRadius && sample.speed < 2
    }

    public mutating func reset() {
        sawAtStop = false; fastFixes = 0; lastAlong = nil; startAlong = nil
    }

    /**
     [line] is the ride's own geometry; [departure] its scheduled (or live) departure; [vehicle] the live
     vehicle position when known.
     */
    public mutating func observe(_ sample: Sample, line: [LatLng], departure: Date?, vehicle: LatLng? = nil) -> Decision {
        guard line.count >= 2, let stop = line.first, sample.accuracy >= 0, sample.accuracy <= 50 else { return .notYet }
        if let departure {
            // A sighting at the stop only counts around the departure, not an hour before.
            let offset = sample.time.timeIntervalSince(departure)
            if waitingAtStop(sample, stop), offset > -15 * 60, offset < 5 * 60 { sawAtStop = true }
            guard offset > -30 else { return .notYet }
        } else if waitingAtStop(sample, stop) {
            sawAtStop = true
        }
        guard sawAtStop else { return .notYet }

        let match = Geo.project(sample.location, on: line)
        let heading = Geo.bearing(Geo.point(along: line, meters: max(0, match.along - 5)),
                                  Geo.point(along: line, meters: match.along + 5))
        var aligned = true
        if sample.course >= 0 {
            let difference = abs(sample.course - heading).truncatingRemainder(dividingBy: 360)
            aligned = min(difference, 360 - difference) <= 50
        }
        let moving = sample.speed >= minimumSpeed && match.offset <= maximumOffsetMeters && aligned
        guard moving else {
            fastFixes = 0; lastAlong = nil; startAlong = nil
            return .notYet
        }
        if let last = lastAlong, match.along < last - 25 {
            fastFixes = 0; lastAlong = nil; startAlong = nil
            return .notYet
        }
        fastFixes += 1
        lastAlong = max(lastAlong ?? 0, match.along)
        startAlong = startAlong ?? match.along
        if let vehicle, sample.location.distance(to: vehicle) > vehicleRadius { return .notYet }
        guard fastFixes >= requiredFixes, let startAlong, (lastAlong ?? 0) - startAlong >= minimumAlongMeters else { return .notYet }
        return .boarded
    }
}

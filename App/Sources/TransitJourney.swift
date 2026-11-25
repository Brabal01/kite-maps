import CoreLocation
import SwiftUI
import VelaCore

@MainActor
final class TransitJourney: ObservableObject {
    enum Phase { case walk, board, ride, complete }
    @Published private(set) var trip: TransitTrip
    @Published private(set) var index = 0
    @Published private(set) var phase: Phase = .walk
    @Published var walking: Navigator?
    @Published var walkingUnavailable = false
    @Published private(set) var nextStop: TransitCall?
    @Published private(set) var nextStopEstimated = false
    var lastConfirmedStop: TransitCall? {
        guard let stopIndex = ride.map({ $0.nextIndex - 1 }), let leg,
              leg.calls.indices.contains(stopIndex) else { return nil }
        return leg.calls.prefix(through: stopIndex).last { !$0.cancelled }
    }
    @Published private(set) var vehicle: Transitous.VehiclePosition?
    @Published private(set) var exitWarning = false
    @Published var following = true
    let destination: Place
    var leg: TransitLeg? { trip.legs.indices.contains(index) ? trip.legs[index] : nil }

    private var nearCount = 0
    private var boarding: TransitBoarding?
    private var ride: TransitRide?
    private var boardedAt: Date?
    private var lastWalkFix: Date?
    private var paceSample: CLLocation?

    init(trip: TransitTrip, destination: Place) {
        self.trip = trip
        self.destination = destination
        prepare()
    }

    private func prepare() {
        phase = leg.map { $0.isWalk ? .walk : .board } ?? .complete
        nextStop = nil
        nextStopEstimated = false
        vehicle = nil
        exitWarning = false
        walkingUnavailable = false
        following = true
        nearCount = 0
        ride = nil
        boardedAt = nil
        lastWalkFix = nil
        paceSample = nil
        prepareBoarding()
    }

    private func prepareBoarding() {
        boarding = nil
        guard phase == .board, let leg, let stop = leg.calls.first?.location ?? leg.path.first else { return }
        boarding = TransitBoarding(path: leg.path, stop: stop)
    }

    func advance() {
        walking?.stop()
        walking = nil
        index += 1
        prepare()
    }

    func board() {
        guard phase == .board, let leg, !leg.cancelled else { return }
        ride = TransitRide(leg: leg)
        boardedAt = Date()
        phase = .ride
        nextStop = leg.calls.dropFirst().first { !$0.cancelled }
    }

    func updateLive(_ updated: TransitTrip?, vehicle: Transitous.VehiclePosition?, at index: Int) {
        guard self.index == index, let previous = leg else { return }
        if let updated, updated.legs.map(\.isWalk) == trip.legs.map(\.isWalk),
           updated.legs.indices.contains(index) {
            let current = updated.legs[index]
            // Keep the booked stop order and the GPS projection through timetable updates.
            let sameStops = current.calls.count == previous.calls.count &&
                zip(previous.calls, current.calls).allSatisfy { old, new in
                    old.location.distance(to: new.location) <= 130 &&
                        ((old.id != nil && old.id == new.id) || old.name == new.name)
                }
            if current.line == previous.line, sameStops || previous.calls.isEmpty {
                trip = updated
                if phase == .board, current.path != previous.path ||
                    current.calls.first?.location != previous.calls.first?.location {
                    prepareBoarding()
                }
                if phase == .ride, previous.calls.isEmpty, !current.calls.isEmpty {
                    ride = TransitRide(leg: current)
                }
            }
        }
        self.vehicle = leg?.cancelled == true ? nil : vehicle
        guard phase == .ride, let leg, let ride, let boardedAt else { return }
        let now = Date()
        if now.timeIntervalSince(ride.lastPositionAt ?? boardedAt) <= 25 {
            nextStop = leg.calls.dropFirst(ride.nextIndex).first { !$0.cancelled }
            return
        }
        guard !leg.cancelled else { return }
        let next = ride.scheduledNext(in: leg.calls, at: now)
        nextStop = next
        nextStopEstimated = next != nil
        if let next, next == leg.calls.last, let arrival = next.arrival ?? leg.arrive,
           (0...75).contains(arrival.timeIntervalSince(now)) {
            warnExit(scheduled: true)
        }
    }

    /// True when guidance can advance to the next leg. Poor or old fixes never change a phase.
    func observe(_ fix: CLLocation, settings: AppSettings) -> Bool {
        let age = Date().timeIntervalSince(fix.timestamp)
        guard let leg, (0...15).contains(age), CLLocationCoordinate2DIsValid(fix.coordinate) else { return false }
        let at = LatLng(fix.coordinate.latitude, fix.coordinate.longitude)
        switch phase {
        case .walk:
            guard (0...50).contains(fix.horizontalAccuracy),
                  lastWalkFix.map({ fix.timestamp > $0 }) ?? true else { return false }
            lastWalkFix = fix.timestamp
            samplePace(fix, settings: settings)
            walking?.handle(fix)
            let goal = trip.legs.dropFirst(index + 1).first?.calls.first?.location ?? leg.path.last
            let close = goal.map { $0.distance(to: at) <= max(18, min(fix.horizontalAccuracy, 30)) } ?? false
            nearCount = close ? nearCount + 1 : 0
            return nearCount >= 2
        case .board:
            guard !leg.cancelled else { return false }
            if boarding?.observe(at, accuracy: fix.horizontalAccuracy, speed: fix.speed, course: fix.course,
                                 at: fix.timestamp, departure: leg.calls.first?.departure ?? leg.depart) == true {
                board()
            }
        case .ride:
            guard let update = ride?.observe(at, accuracy: fix.horizontalAccuracy, speed: fix.speed, at: fix.timestamp),
                  let nextIndex = ride?.nextIndex, leg.calls.indices.contains(nextIndex) else { return false }
            nextStop = leg.calls.dropFirst(nextIndex).first { !$0.cancelled }
            nextStopEstimated = false
            if update.exitApproach { warnExit(scheduled: false) }
            return update.readyToExit
        case .complete: break
        }
        return false
    }

    private func samplePace(_ fix: CLLocation, settings: AppSettings) {
        guard settings.learnWalkingPace, Date().timeIntervalSince(fix.timestamp) <= 5,
              fix.horizontalAccuracy <= 18, (0.65...2.2).contains(fix.speed) else {
            paceSample = nil
            return
        }
        guard let previous = paceSample else { paceSample = fix; return }
        let seconds = fix.timestamp.timeIntervalSince(previous.timestamp)
        guard seconds >= 18 else { return }
        paceSample = fix
        guard seconds <= 40, fix.distance(from: previous) / seconds >= 0.5 else { return }
        let pace = (fix.speed + previous.speed) / 2
        settings.walkingPace = settings.personalPace.map { $0 * 0.8 + pace * 0.2 } ?? pace
    }

    private func warnExit(scheduled: Bool) {
        guard !exitWarning, let stop = leg?.toName, !stop.isEmpty else { return }
        exitWarning = true
        guard AppSettings.shared.transitExitAlerts else { return }
        Task { await TransitReminders.exit(stop: stop, scheduled: scheduled) }
    }
}

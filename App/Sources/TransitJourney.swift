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
    @Published private(set) var vehicle: Transitous.VehiclePosition?
    @Published private(set) var exitWarning = false
    @Published var following = true
    let destination: Place
    var leg: TransitLeg? { trip.legs.indices.contains(index) ? trip.legs[index] : nil }

    private var nearCount = 0
    private var seenAtStop = false
    private var movingCount = 0
    private var progress = 0.0
    private var lastMatched: Date?
    private var cumulative: [Double] = []
    private var callDistances: [Double] = []
    private var paceSample: CLLocation?

    init(trip: TransitTrip, destination: Place) {
        self.trip = trip
        self.destination = destination
        prepare()
    }

    private func prepare() {
        phase = leg.map { $0.isWalk ? .walk : .board } ?? .complete
        nextStop = nil
        vehicle = nil
        exitWarning = false
        walkingUnavailable = false
        following = true
        nearCount = 0
        seenAtStop = false
        movingCount = 0
        progress = 0
        lastMatched = nil
        paceSample = nil
        cacheGeometry()
    }

    private func cacheGeometry() {
        guard let leg else { cumulative = []; callDistances = []; return }
        cumulative = Geo.cumulative(leg.path)
        callDistances = leg.path.count >= 2 ? leg.calls.map {
            Geo.project($0.location, on: leg.path, cumulative: cumulative).along
        } : []
    }

    func advance() {
        walking?.stop()
        walking = nil
        index += 1
        prepare()
    }

    func board() {
        guard phase == .board else { return }
        phase = .ride
        nextStop = leg?.calls.dropFirst().first
        lastMatched = nil
        nearCount = 0
    }

    func updateLive(_ updated: TransitTrip?, vehicle: Transitous.VehiclePosition?, at index: Int) {
        guard self.index == index else { return }
        if let updated, updated.legs.map(\.isWalk) == trip.legs.map(\.isWalk) {
            if leg?.path != updated.legs[index].path {
                trip = updated
                cacheGeometry()
            } else { trip = updated }
        }
        self.vehicle = vehicle
        guard phase == .ride, lastMatched.map({ Date().timeIntervalSince($0) > 25 }) ?? true,
              leg?.cancelled == false else { return }
        let next = leg?.calls.dropFirst().first { $0.arrival.map { $0 >= Date() } == true }
        if let next { nextStop = next }
        if let next, next == leg?.calls.last, let at = next.arrival, at.timeIntervalSinceNow <= 75 {
            warnExit(scheduled: true)
        }
    }

    /// True when guidance can advance to the next leg. Poor or old fixes never change a phase.
    func observe(_ fix: CLLocation, settings: AppSettings) -> Bool {
        guard let leg, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 50,
              abs(fix.timestamp.timeIntervalSinceNow) <= 15 else { return false }
        let at = LatLng(fix.coordinate.latitude, fix.coordinate.longitude)
        switch phase {
        case .walk:
            samplePace(fix, settings: settings)
            walking?.handle(fix)
            let goal = trip.legs.dropFirst(index + 1).first?.calls.first?.location ?? leg.path.last
            let close = goal.map { $0.distance(to: at) <= max(18, min(fix.horizontalAccuracy, 30)) } ?? false
            nearCount = close ? nearCount + 1 : 0
            return nearCount >= 2
        case .board:
            guard let stop = leg.calls.first?.location ?? leg.path.first else { return false }
            if at.distance(to: stop) <= 55 { seenAtStop = true }
            guard seenAtStop, let departure = leg.depart, abs(fix.timestamp.timeIntervalSince(departure)) < 12 * 60,
                  leg.path.count >= 2 else { return false }
            let projected = Geo.project(at, on: leg.path, cumulative: cumulative)
            movingCount = fix.speed >= 3 && projected.along >= 60 && projected.offset <= 30 ? movingCount + 1 : 0
            if movingCount >= 2 { board() }
        case .ride:
            if leg.path.count >= 2 {
                let projected = Geo.project(at, on: leg.path, cumulative: cumulative)
                if projected.offset <= 55 && projected.along + 100 >= progress {
                    progress = max(progress, projected.along)
                    lastMatched = fix.timestamp
                    if let upcoming = callDistances.indices.dropFirst().first(where: { callDistances[$0] >= progress + 12 }) {
                        nextStop = leg.calls[upcoming]
                        if upcoming == leg.calls.count - 1 && callDistances[upcoming] - progress < 300 { warnExit(scheduled: false) }
                    }
                }
            }
            if let exit = leg.calls.last?.location ?? leg.path.last {
                let close = exit.distance(to: at) < 35 && (fix.speed < 4)
                nearCount = close ? nearCount + 1 : 0
                return nearCount >= 2 && (callDistances.last.map { progress >= $0 - 120 } ?? true)
            }
        case .complete: break
        }
        return false
    }

    private func samplePace(_ fix: CLLocation, settings: AppSettings) {
        guard settings.learnWalkingPace, fix.horizontalAccuracy <= 18, (0.65...2.2).contains(fix.speed) else {
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

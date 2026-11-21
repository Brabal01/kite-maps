import CoreLocation
import Foundation
import VelaCore

/**
 Deterministic data for the simulator UI test. Production builds never see
 it: every entry point checks for the launch arguments below first.
 */
enum UITestSupport {
    static var planning: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-planning")
    }

    static var mockRoutes: Bool {
        ProcessInfo.processInfo.environment["KITE_UITEST_ROUTES"] == "1"
    }

    static var simulatedCoordinate: CLLocationCoordinate2D? {
        guard let raw = ProcessInfo.processInfo.environment["KITE_UITEST_LOCATION"] else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, abs(parts[0]) <= 90, abs(parts[1]) <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: parts[0], longitude: parts[1])
    }

    static var simulatedLocationDelay: TimeInterval {
        guard let raw = ProcessInfo.processInfo.environment["KITE_UITEST_LOCATION_DELAY"],
              let value = Double(raw) else { return 0.8 }
        return min(10, max(0, value))
    }

    static func simulatedLocation() -> CLLocation? {
        guard let coordinate = simulatedCoordinate else { return nil }
        return CLLocation(coordinate: coordinate, altitude: 0,
                          horizontalAccuracy: 5, verticalAccuracy: 5,
                          course: 0, speed: 0, timestamp: Date())
    }

    /** Put the app on the Routes page with two favourites, ready to plan. */
    @MainActor
    static func install(_ model: AppModel) {
        guard planning else { return }
        let here = simulatedCoordinate.map { LatLng($0.latitude, $0.longitude) }
            ?? LatLng(38.5449, -121.7405)
        model.settings.welcomed = true
        model.settings.wazeAsked = true
        model.settings.noGoogle = false
        model.settings.theme = .light
        model.settings.home = Place(id: "uitest-home", name: "Home", location: here, source: "demo")
        var work = Place(id: "uitest-work", name: "Work",
                         location: LatLng(here.lat + 0.0072, here.lng - 0.0062), source: "demo")
        work.address = "Test Street 1"
        model.settings.work = work
        model.settings.recentPlaces = [work]
        model.tab = .routes
    }

    /** A synthetic but structurally real route, with turn-by-turn steps. */
    static func routes(from: LatLng, to: LatLng, mode: TravelMode, avoidHighways: Bool = false) -> [Route] {
        guard from != to else { return [] }
        let distance = from.distance(to: to)
        let speed: Double = mode == .drive ? 13.9 : mode == .bike ? 4.5 : 1.35
        var seconds = max(60, distance / speed)
        if avoidHighways { seconds *= 1.15 }
        let middle = LatLng((from.lat + to.lat) / 2 + 0.0009, (from.lng + to.lng) / 2)
        let path = [from, middle, to]
        let length = Geo.length(path)
        let maneuvers = [
            Maneuver(type: .depart, instruction: "Head out", location: from,
                     alongMeters: 0, distanceMeters: length / 2),
            Maneuver(type: .turnRight, instruction: "Turn right", location: middle,
                     alongMeters: length / 2, distanceMeters: length / 2),
            Maneuver(type: .arrive, instruction: "Arrive", location: to,
                     alongMeters: length, distanceMeters: 0)
        ]
        return [Route(mode: mode, polyline: path, distanceMeters: length,
                      typicalSeconds: seconds, trafficSeconds: nil,
                      summary: "Test route", maneuvers: maneuvers, source: "test")]
    }

    static func transitTrips(from: LatLng, to: LatLng) -> [TransitTrip] {
        let walk = TransitLeg(isWalk: true, mode: "WALK", line: "", fromName: "Home", toName: "Central",
                              durationSeconds: 6 * 60, distanceMeters: 480, path: [from, to])
        let ride = TransitLeg(isWalk: false, mode: "BUS", line: "42", headsign: "Central",
                              fromName: "Central", toName: "Work", durationSeconds: 18 * 60,
                              distanceMeters: from.distance(to: to), stops: 6, path: [to])
        let now = Date()
        return [TransitTrip(depart: now.addingTimeInterval(4 * 60),
                            arrive: now.addingTimeInterval(28 * 60),
                            durationSeconds: 24 * 60, transfers: 0, legs: [walk, ride])]
    }
}

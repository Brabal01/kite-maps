import CoreLocation
import Foundation
import UIKit
import VelaCore

/** GPS for search bias and navigation. The map draws its own blue dot; this feeds the app. */
@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private var fix: CLLocation?
    func navigationFix(maximumError: Double) -> CLLocation? {
        guard !reducedAccuracy, let fix,
              RouteTracker.isFreshFix(age: Date().timeIntervalSince(fix.timestamp), accuracy: fix.horizontalAccuracy, maximumError: maximumError) else { return nil }
        return fix
    }

    var last: CLLocation? {
        guard let fix, Date().timeIntervalSince(fix.timestamp) <= 15 else { return nil }
        return fix
    }
    @Published private(set) var authorized = false
    /** Location is off for Kite (or for the whole phone): only Settings can turn it back on. */
    @Published private(set) var denied = false
    @Published private(set) var reducedAccuracy = false
    /** The phone's compass, true north when iOS has it, magnetic otherwise. Nil while the compass is off or unreliable. */
    @Published private(set) var deviceHeading: Double?
    var onUpdate: (@MainActor (CLLocation) -> Void)?
    private let manager = CLLocationManager()
    private var navigating = false
    private var requestedPreciseLocation = false
    private var headingOn = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .other
        reducedAccuracy = manager.accuracyAuthorization == .reducedAccuracy
    }

    func start() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
        startHeading()
    }

    /** The map turns to the compass on open; stop the compass when Kite goes to the background. */
    func startHeading() {
        guard !headingOn else { return }
        headingOn = true
        manager.startUpdatingHeading()
    }

    func stopHeading() {
        guard headingOn else { return }
        headingOn = false
        manager.stopUpdatingHeading()
    }

    func requestPreciseLocation() {
        guard authorized, reducedAccuracy, !requestedPreciseLocation else { return }
        requestedPreciseLocation = true
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "PreciseNavigation")
    }

    /** Full-rate GPS that keeps running with the screen off, for a drive. */
    func setNavigating(_ on: Bool, mode: Int = 0) {
        navigating = on
        manager.activityType = on ? (mode == 0 ? .automotiveNavigation : .fitness) : .other
        manager.distanceFilter = kCLDistanceFilterNone
        manager.desiredAccuracy = on ? kCLLocationAccuracyBestForNavigation : kCLLocationAccuracyBest
        manager.allowsBackgroundLocationUpdates = on
        manager.pausesLocationUpdatesAutomatically = !on
        manager.showsBackgroundLocationIndicator = on
        start()
        if on { requestPreciseLocation() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // A negative accuracy means the compass is calibrating; a huge error is a magnetic
        // disturbance (a car roof, a phone case). Neither may swing the map.
        guard newHeading.headingAccuracy >= 0, newHeading.headingAccuracy <= 45,
              abs(newHeading.timestamp.timeIntervalSinceNow) < 5 else { return }
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        guard (0..<360).contains(value) else { return }
        Task { @MainActor in
            self.deviceHeading = value
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            let age = self.navigating ? 8.0 : 15.0
            let maximumError = self.reducedAccuracy ? 20_000.0 : 250.0
            guard let loc = locations.filter({
                (0...maximumError).contains($0.horizontalAccuracy) &&
                (-2...age).contains(Date().timeIntervalSince($0.timestamp))
            }).max(by: { $0.timestamp < $1.timestamp }) else { return }
            if let earlier = self.fix {
                let elapsed = loc.timestamp.timeIntervalSince(earlier.timestamp)
                guard elapsed > 0 else { return }
                if elapsed < 5, loc.horizontalAccuracy > max(25, earlier.horizontalAccuracy * 2),
                   loc.distance(from: earlier) > max(12, earlier.speed) * elapsed + earlier.horizontalAccuracy {
                    return
                }
            }
            self.fix = loc
            self.onUpdate?(loc)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        let reduced = manager.accuracyAuthorization == .reducedAccuracy
        Task { @MainActor in
            self.authorized = s == .authorizedWhenInUse || s == .authorizedAlways
            self.denied = s == .denied || s == .restricted
            self.reducedAccuracy = reduced
            if self.authorized {
                self.manager.startUpdatingLocation()
                self.startHeading()
                if self.navigating { self.requestPreciseLocation() }
            } else {
                self.fix = nil
                self.deviceHeading = nil
                self.stopHeading()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    /** Kite's page in the Settings app, where location can be turned back on. */
    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

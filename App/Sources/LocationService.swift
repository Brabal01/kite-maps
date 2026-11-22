import CoreLocation
import Foundation
import UIKit
import VelaCore

/** GPS for search bias, route planning and navigation. The map draws its own blue dot; this feeds the app. */
@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private var fix: CLLocation?
    @Published private(set) var authorized = false
    /** Location is off for Kite (or for the whole phone): only Settings can turn it back on. */
    @Published private(set) var denied = false
    @Published private(set) var locationServicesOff = false
    /** Shorter name for the views. */
    var servicesOff: Bool { locationServicesOff }
    @Published private(set) var reducedAccuracy = false
    /** The phone's compass, true north when iOS has it, magnetic otherwise. Nil while the compass is off or unreliable. */
    @Published private(set) var deviceHeading: Double?
    var onUpdate: (@MainActor (CLLocation) -> Void)?

    /**
     The forced one-shot request that a planner makes on opening. It is
     separate from the continuous stream so the UI can tell "we are asking
     now" from "we had a fix a while ago".
     */
    enum PlanningRequestState: Equatable {
        case idle
        case requesting
        case received(at: Date)
        case timedOut
        case paused
        case failed
    }
    @Published private(set) var planningState: PlanningRequestState = .idle
    /** Called when iOS pauses updates or the app returns after a lock, so planning can ask again. */
    var onPlanningInterrupted: (@MainActor () -> Void)?
    /** Authorization and phone-wide location-service changes, for the planner's own state. */
    var onAuthorizationChanged: (@MainActor (_ granted: Bool, _ denied: Bool, _ servicesOff: Bool) -> Void)?

    private let manager = CLLocationManager()
    private var navigating = false
    private var requestedPreciseLocation = false
    private var headingOn = false
    private var foreground = true
    private var currentMode: Mode = .browse

    // Planning lifecycle. One manager, one request; never competing instances.
    private var planningActive = false
    private var planningRequestInFlight = false
    private var planningWatchdog: Task<Void, Never>?
    private var planningResumeContinuous = false
    private var oneShotOutstanding = false
    private var simulatedTask: Task<Void, Never>?
    private var navigationMode: Mode?

    /** How much GPS the current screen actually needs. */
    enum Mode {
        case browse
        case planning
        case justDrive
        case navigateDrive
        case navigateWalkOrBike
        case transit
    }

    override init() {
        super.init()
        LaunchTrace.mark("LocationService init")
        manager.delegate = self
        apply(.browse)
        reducedAccuracy = manager.accuracyAuthorization == .reducedAccuracy
        let status = manager.authorizationStatus
        authorized = status == .authorizedWhenInUse || status == .authorizedAlways
        denied = status == .denied || status == .restricted
        locationServicesOff = !CLLocationManager.locationServicesEnabled()
    }

    /// The generated Info.plist must contain the location background mode. Setting
    /// `allowsBackgroundLocationUpdates` without it raises an Objective-C exception on iOS.
    private var backgroundLocationAllowed: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?.contains("location") == true
    }

    private func setBackgroundLocation(_ on: Bool) {
        guard backgroundLocationAllowed else { return }
        // Activating background updates is only valid while the app is in the foreground.
        if on, UIApplication.shared.applicationState == .background { return }
        manager.allowsBackgroundLocationUpdates = on
        manager.showsBackgroundLocationIndicator = on
    }

    private func apply(_ mode: Mode) {
        currentMode = mode
        switch mode {
        case .browse:
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            manager.distanceFilter = 15
            manager.activityType = .other
            manager.pausesLocationUpdatesAutomatically = true
            setBackgroundLocation(false)
        case .planning:
            // Actively power up the GPS for a fresh start point, then fall back
            // to a modest filter once a fix arrives. No background mode and no
            // Always permission is needed just to plan a route.
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = kCLDistanceFilterNone
            manager.activityType = .other
            manager.pausesLocationUpdatesAutomatically = false
            setBackgroundLocation(false)
        case .justDrive:
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = 5
            manager.activityType = .automotiveNavigation
            manager.pausesLocationUpdatesAutomatically = false
            setBackgroundLocation(true)
        case .navigateDrive:
            manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            manager.distanceFilter = kCLDistanceFilterNone
            manager.activityType = .automotiveNavigation
            manager.pausesLocationUpdatesAutomatically = false
            setBackgroundLocation(true)
        case .navigateWalkOrBike:
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = 2
            manager.activityType = .fitness
            manager.pausesLocationUpdatesAutomatically = false
            setBackgroundLocation(true)
        case .transit:
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = 5
            manager.activityType = .fitness
            manager.pausesLocationUpdatesAutomatically = false
            setBackgroundLocation(true)
        }
    }

    // MARK: Fixes by purpose

    /** Recent enough to draw the map and centre on you. */
    var last: CLLocation? {
        guard let fix, Date().timeIntervalSince(fix.timestamp) <= 60,
              fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 500 else { return nil }
        return fix
    }

    /** The last known fix, even if older: search distances and a labelled fallback. */
    var lastKnown: CLLocation? {
        guard let fix, Date().timeIntervalSince(fix.timestamp) <= 15 * 60,
              fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 20_000 else { return nil }
        return fix
    }

    /** Approximate is fine for centring search results. */
    var searchFix: CLLocation? {
        guard let fix, Date().timeIntervalSince(fix.timestamp) <= 5 * 60,
              fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 5_000 else { return nil }
        return fix
    }

    /**
     A fix as the planner sees it. The session classifies it as fresh,
     approximate, stale or expired; this only refuses nonsense.
     */
    /** A valid current-position fix, never an invalid coordinate or a clock from the future. */
    private func hasValidPosition(_ loc: CLLocation, at now: Date = Date()) -> Bool {
        let c = loc.coordinate
        return c.latitude.isFinite && c.longitude.isFinite &&
            (-90...90).contains(c.latitude) && (-180...180).contains(c.longitude) &&
            !(c.latitude == 0 && c.longitude == 0) &&
            loc.timestamp.timeIntervalSince(now) <= 2
    }

    func planningFix(at now: Date = Date()) -> PlanningFix? {
        guard let fix, hasValidPosition(fix, at: now) else { return nil }
        let age = now.timeIntervalSince(fix.timestamp)
        guard age <= 15 * 60, fix.horizontalAccuracy >= 0,
              fix.horizontalAccuracy <= 20_000 else { return nil }
        return PlanningFix(point: LatLng(fix.coordinate.latitude, fix.coordinate.longitude),
                           timestamp: fix.timestamp, horizontalAccuracy: fix.horizontalAccuracy)
    }

    /** A navigation-grade fix, still strict about position, age and accuracy. */
    func navigationFix(maximumError: Double) -> CLLocation? {
        let now = Date()
        guard !reducedAccuracy, let fix, hasValidPosition(fix, at: now),
              RouteTracker.isFreshFix(age: now.timeIntervalSince(fix.timestamp),
                                      accuracy: fix.horizontalAccuracy,
                                      maximumError: maximumError) else { return nil }
        return fix
    }

    /** The last known fix kept for a short GPS outage, never invented from the map centre. */
    var estimatedFix: CLLocation? {
        guard let fix, Date().timeIntervalSince(fix.timestamp) <= 5 * 60,
              fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 500 else { return nil }
        return fix
    }

    // MARK: Lifecycle

    func start() {
        // The simulator UI test supplies its own fix; never raise a system
        // permission alert that the test runner would have to dismiss.
        if UITestSupport.planning { return }
        LaunchTrace.mark("LocationService start")
        let status = manager.authorizationStatus
        if status == .notDetermined { manager.requestWhenInUseAuthorization() }
        guard foreground else { return }
        if planningActive {
            // The planner owns the request; don't fight it with a second start.
            if !planningRequestInFlight, planningState != .requesting { manager.startUpdatingLocation() }
        } else {
            manager.startUpdatingLocation()
        }
        startHeading()
    }

    /** Stop the high-rate GPS when the map is not visible; navigation keeps running in the background. */
    func setForeground(_ on: Bool) {
        foreground = on
        if on {
            if planningActive {
                // A locked phone or a return from the background must ask again.
                refreshPlanningLocation()
            } else {
                start()
            }
        } else {
            stopHeading()
            if !navigating {
                manager.stopUpdatingLocation()
                if planningActive { planningState = .paused }
            }
        }
    }

    /**
     Open the planner's GPS session. This actively asks for a fresh fix even
     when the user is sitting still, using one CLLocationManager.
     */
    func beginPlanning(refresh: Bool = true) {
        LaunchTrace.mark("LocationService planning")
        planningActive = true
        if UITestSupport.planning {
            apply(.planning)
            scheduleSimulatedPlanningFix()
            return
        }
        let status = manager.authorizationStatus
        if status == .notDetermined { manager.requestWhenInUseAuthorization() }
        locationServicesOff = !CLLocationManager.locationServicesEnabled()
        guard foreground, authorized || status == .notDetermined else {
            planningState = denied || locationServicesOff ? .failed : .requesting
            return
        }
        apply(.planning)
        if refresh {
            refreshPlanningLocation()
        } else {
            manager.startUpdatingLocation()
        }
    }

    /** The user tapped "Try again", or the app came back to the planner. */
    func retryPlanningLocation() {
        guard planningActive else {
            beginPlanning()
            return
        }
        if UITestSupport.planning {
            apply(.planning)
            scheduleSimulatedPlanningFix()
            return
        }
        if !foreground { return }
        apply(.planning)
        refreshPlanningLocation()
    }

    /** Simulator UI tests: feed a fix through exactly the same update path. */
    private func scheduleSimulatedPlanningFix() {
        simulatedTask?.cancel()
        guard let loc = UITestSupport.simulatedLocation() else {
            planningState = .failed
            return
        }
        planningRequestInFlight = true
        planningState = .requesting
        let delay = UITestSupport.simulatedLocationDelay
        simulatedTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1e9))
            }
            guard !Task.isCancelled, let self, self.planningActive, self.foreground else { return }
            self.planningRequestInFlight = false
            self.fix = loc
            self.planningState = .received(at: loc.timestamp)
            self.onUpdate?(loc)
        }
    }

    /** Back to the power-saving browse mode once the planner closes. */
    func endPlanning() {
        guard planningActive || planningState != .idle else { return }
        planningActive = false
        simulatedTask?.cancel()
        simulatedTask = nil
        planningRequestInFlight = false
        planningResumeContinuous = false
        // Leave oneShotOutstanding set: when that answer arrives we restart the
        // browse stream, because requestLocation stops continuous updates.
        planningWatchdog?.cancel()
        planningWatchdog = nil
        planningState = .idle
        if let navigationMode {
            apply(navigationMode)
            if foreground { manager.startUpdatingLocation() }
        } else if foreground {
            apply(.browse)
            manager.startUpdatingLocation()
        } else {
            apply(.browse)
            manager.stopUpdatingLocation()
        }
    }

    /**
     `requestLocation()` and continuous updates do not coexist safely on iOS: a
     one-shot request makes the manager stop the continuous stream after it
     answers. So planning deliberately stops the stream, asks for one fresh
     fix, and restores the stream afterwards. A watchdog restores it too if the
     answer never comes.
     */
    private func refreshPlanningLocation() {
        guard planningActive, foreground else { return }
        if planningRequestInFlight { return }
        planningRequestInFlight = true
        planningResumeContinuous = true
        oneShotOutstanding = true
        planningState = .requesting
        manager.stopUpdatingLocation()
        manager.requestLocation()
        planningWatchdog?.cancel()
        planningWatchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled else { return }
            self?.planningWatchdogFired()
        }
    }

    private func planningWatchdogFired() {
        guard planningActive, planningRequestInFlight else { return }
        planningRequestInFlight = false
        oneShotOutstanding = false
        planningState = .timedOut
        if planningResumeContinuous {
            planningResumeContinuous = false
            if foreground { manager.startUpdatingLocation() }
        }
    }

    private func finishPlanningRequest(_ loc: CLLocation) {
        oneShotOutstanding = false
        guard planningRequestInFlight else { return }
        planningRequestInFlight = false
        planningWatchdog?.cancel()
        planningWatchdog = nil
        planningState = .received(at: loc.timestamp)
        if planningResumeContinuous, planningActive, foreground {
            planningResumeContinuous = false
            // Keep receiving movement updates after the forced fresh fix.
            apply(.planning)
            manager.startUpdatingLocation()
        }
    }

    /** The planner closes: stop asking, but keep the manager for the map. */
    func cancelPlanningRequest() {
        planningWatchdog?.cancel()
        planningWatchdog = nil
        planningRequestInFlight = false
        planningResumeContinuous = false
        oneShotOutstanding = false
    }

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
    func setNavigating(_ on: Bool, mode: Int = 0, transit: Bool = false, justDrive: Bool = false) {
        navigating = on
        if !on {
            navigationMode = nil
            if planningActive {
                apply(.planning)
                if foreground { manager.startUpdatingLocation() }
            } else {
                apply(.browse)
            }
        } else {
            let chosen: Mode
            if justDrive {
                chosen = .justDrive
            } else if transit {
                chosen = .transit
            } else if mode == TravelMode.drive.rawValue {
                chosen = .navigateDrive
            } else {
                chosen = .navigateWalkOrBike
            }
            navigationMode = chosen
            apply(chosen)
        }
        if on, UITestSupport.offline {
            simulatedTask?.cancel()
            simulatedTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled, let self, self.navigating,
                      let loc = UITestSupport.simulatedLocation() else { return }
                self.fix = loc
                self.onUpdate?(loc)
            }
            return
        }
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
            // Accept a last-known fix much longer than the old 15 seconds: the
            // consumer decides whether it is fresh, approximate or stale.
            let maximumAge = self.navigating ? 30.0 : 15 * 60.0
            let maximumError = self.reducedAccuracy ? 20_000.0 : 2_000.0
            let now = Date()
            guard let loc = locations.filter({
                $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy.isFinite &&
                (0...maximumError).contains($0.horizontalAccuracy) &&
                (-2...maximumAge).contains(now.timeIntervalSince($0.timestamp)) &&
                self.hasValidPosition($0, at: now)
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
            self.finishPlanningRequest(loc)
            // A one-shot request also stops continuous updates. If the planner
            // has already closed, restore the browse stream that it interrupted.
            if !self.planningActive, self.foreground {
                self.manager.startUpdatingLocation()
            }
            self.onUpdate?(loc)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        let reduced = manager.accuracyAuthorization == .reducedAccuracy
        let servicesOff = !CLLocationManager.locationServicesEnabled()
        Task { @MainActor in
            self.authorized = s == .authorizedWhenInUse || s == .authorizedAlways
            self.denied = s == .denied || s == .restricted
            self.locationServicesOff = servicesOff
            self.reducedAccuracy = reduced
            self.onAuthorizationChanged?(self.authorized, self.denied, servicesOff)
            if self.authorized {
                if self.planningActive {
                    self.apply(.planning)
                    self.refreshPlanningLocation()
                } else {
                    self.manager.startUpdatingLocation()
                }
                self.startHeading()
                if self.navigating { self.requestPreciseLocation() }
            } else {
                self.fix = nil
                self.deviceHeading = nil
                self.stopHeading()
                if self.planningActive, self.denied || self.locationServicesOff {
                    self.planningState = .failed
                }
            }
        }
    }

    /** iOS may pause continuous updates by itself even with the flag off; resume and retry. */
    nonisolated func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.foreground else { return }
            self.planningState = .paused
            if self.navigating {
                self.manager.startUpdatingLocation()
            } else if self.planningActive {
                self.onPlanningInterrupted?()
                self.refreshPlanningLocation()
            } else {
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        Task { @MainActor in
            if self.planningActive, self.foreground {
                self.refreshPlanningLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            let code = (error as? CLError)?.code
            if code == .denied {
                self.denied = true
                self.fix = nil
                if self.planningActive { self.planningState = .failed }
                return
            }
            if code == .locationUnknown {
                // A transient failure: the watchdog or the next real fix handles it.
                // The one-shot request is over either way, so restart the stream.
                if self.oneShotOutstanding {
                    self.oneShotOutstanding = false
                    self.planningRequestInFlight = false
                    if self.foreground { self.manager.startUpdatingLocation() }
                }
                return
            }
            if self.planningActive { self.planningState = .failed }
        }
    }

    /** Kite's page in the Settings app, where location can be turned back on. */
    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

import CoreLocation
import Foundation
import VelaCore

@MainActor
final class JurisdictionService {
    private let settings: AppSettings
    private var coordinator: JurisdictionCoordinator?
    private var routeID: UUID?
    private var cumulative: [Double] = []

    init(settings: AppSettings) { self.settings = settings }

    func update(_ location: CLLocation, navigator: Navigator) {
        let route = navigator.route
        if routeID != route.id {
            routeID = route.id
            cumulative = Geo.cumulative(route.polyline)
        }
        let lookahead = navigator.progress.map {
            Geo.point(along: route.polyline, meters: $0.alongMeters + 750, cumulative: cumulative)
        }
        if coordinator == nil { coordinator = JurisdictionCoordinator() }
        guard let decision = coordinator?.update(
            position: LatLng(location.coordinate.latitude, location.coordinate.longitude),
            accuracy: location.horizontalAccuracy, timestamp: location.timestamp, now: Date(),
            routeLookahead: lookahead
        ) else { return }
        if settings.cameraCountryCode != decision.countryCode {
            settings.cameraCountryCode = decision.countryCode
        }
        if settings.cameraJurisdiction != decision.policy { settings.cameraJurisdiction = decision.policy }
    }

    func invalidate() {
        if settings.cameraCountryCode != nil { settings.cameraCountryCode = nil }
        if settings.cameraJurisdiction != .unknown { settings.cameraJurisdiction = .unknown }
    }

    func reset() {
        coordinator?.reset()
        routeID = nil
        cumulative = []
        invalidate()
    }
}

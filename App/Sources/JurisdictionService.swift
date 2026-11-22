import CoreLocation
import Foundation
import VelaCore

/**
 Resolves the country the vehicle is actually in, using Core Location's reverse geocoder. It is asked
 once when a journey starts (or when the offline journey is resumed), cached for the session and
 never inferred from the interface language. A failed lookup stays "unknown", which means camera
 warnings are off unless the user explicitly accepted responsibility.
 */
@MainActor
final class JurisdictionService {
    static let shared = JurisdictionService()

    private let geocoder = CLGeocoder()
    private var cache: [String: CameraWarningPolicy] = [:]
    private var task: Task<Void, Never>?

    func resolve(_ coordinate: LatLng) async -> CameraWarningPolicy {
        // About 0.01°: the same town, so a cached answer is still the right jurisdiction.
        let key = "\(Int(coordinate.lat * 100)),\(Int(coordinate.lng * 100))"
        if let cached = cache[key] { return cached }
        task?.cancel()
        let task = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            let location = CLLocation(latitude: coordinate.lat, longitude: coordinate.lng)
            let country = try? await self.geocoder.reverseGeocodeLocation(location).first?.isoCountryCode
            let policy = CameraJurisdiction.policy(isoCountryCode: country)
            guard !Task.isCancelled else { return }
            self.cache[key] = policy
            AppSettings.shared.cameraJurisdiction = policy
        }
        self.task = task
        await task.value
        return AppSettings.shared.cameraJurisdiction
    }

    func forget() {
        task?.cancel()
        task = nil
        cache = [:]
        AppSettings.shared.cameraJurisdiction = .unknown
    }
}

import XCTest
@testable import VelaCore

final class JurisdictionCoordinatorTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_000)

    private func coordinator() throws -> JurisdictionCoordinator {
        func region(_ code: String, west: Double, east: Double) throws -> CountryBoundaries.Polygon {
            try XCTUnwrap(.init(code: code, rings: [[LatLng(49, west), LatLng(49, east),
                                                    LatLng(51, east), LatLng(51, west), LatLng(49, west)]]))
        }
        return JurisdictionCoordinator(boundaries: CountryBoundaries(polygons: [
            try region("CZ", west: 12, east: 13), try region("DE", west: 13, east: 14)
        ]), boundaryBuffer: 0)
    }

    func testCrossBorderInBothDirectionsAndAvoidUsingRouteDestinationAsCountry() throws {
        var coordinator = try coordinator()
        let route = [LatLng(50, 12.9), LatLng(50, 13), LatLng(50, 13.1)]
        for (index, point) in (route + route.dropLast().reversed()).enumerated() {
            let now = time.addingTimeInterval(Double(index))
            let decision = coordinator.update(position: point, accuracy: 10, timestamp: now, now: now,
                                              routeLookahead: route.last)
            XCTAssertEqual(decision.policy, [.allowed, .unknown, .restricted, .unknown, .allowed][index])
        }
    }

    func testUncertainOrStaleFixFailsClosedAfterAllowedFix() throws {
        var coordinator = try coordinator()
        let deep = LatLng(50, 12.99)
        XCTAssertEqual(coordinator.update(position: deep, accuracy: 8, timestamp: time, now: time).countryCode, "CZ")
        let now = time.addingTimeInterval(1)
        XCTAssertEqual(coordinator.update(position: LatLng(50, 12.9999), accuracy: 30, timestamp: now, now: now).policy, .unknown)
        XCTAssertEqual(coordinator.update(position: deep, accuracy: -1, timestamp: now, now: now).policy, .unknown)
        XCTAssertEqual(coordinator.update(position: deep, accuracy: 4, timestamp: time, now: time.addingTimeInterval(10)).policy, .unknown)
    }

    func testBundledCzechGermanAndSlovakCoverage() {
        var coordinator = JurisdictionCoordinator()
        for (point, expected) in [(LatLng(49.5938, 17.2509), "CZ"), (LatLng(51.0504, 13.7373), "DE"),
                                  (LatLng(48.7164, 21.2611), "SK")] {
            let result = coordinator.update(position: point, accuracy: 5, timestamp: time, now: time)
            XCTAssertEqual(result.countryCode, expected)
        }
    }
}

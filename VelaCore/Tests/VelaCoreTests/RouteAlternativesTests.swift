import XCTest
@testable import VelaCore

final class RouteAlternativesTests: XCTestCase {
    private func route(_ seconds: Double, _ meters: Double, summary: String? = nil) -> Route {
        Route(mode: .drive,
              polyline: [LatLng(50, -1), LatLng(50.01, -1.01)],
              distanceMeters: meters,
              typicalSeconds: seconds,
              trafficSeconds: nil,
              summary: summary,
              maneuvers: [],
              source: "osm")
    }

    func testKeepsTheFastestFirst() {
        let slow = route(900, 10_000, summary: "slow")
        let fast = route(600, 11_000, summary: "fast")
        let kept = RouteAlternatives.distinct([slow, fast])
        XCTAssertEqual(kept.map(\.summary), ["fast", "slow"])
    }

    func testDropsNearIdenticalAlternatives() {
        let best = route(900, 10_000, summary: "best")
        let sameRoad = route(910, 10_050, summary: "same")
        let kept = RouteAlternatives.distinct([best, sameRoad])
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept.first?.summary, "best")
    }

    func testKeepsAClearlyDifferentRoadEvenWhenSlower() {
        let best = route(900, 10_000, summary: "motorway")
        let other = route(1_200, 11_500, summary: "country road")
        let kept = RouteAlternatives.distinct([best, other])
        XCTAssertEqual(kept.map(\.summary), ["motorway", "country road"])
    }

    func testKeepsAShorterRouteWithASimilarTime() {
        let best = route(900, 12_000, summary: "fast")
        let shorter = route(930, 8_500, summary: "short")
        let kept = RouteAlternatives.distinct([best, shorter])
        XCTAssertEqual(kept.map(\.summary), ["fast", "short"])
    }

    func testToleranceGrowsWithLongTrips() {
        // A 10 second difference on a 10 minute trip is noise; on a 10 hour trip
        // three minutes also changes nothing for the driver.
        let long = route(36_000, 700_000, summary: "long")
        let almost = route(36_120, 700_400, summary: "almost")
        XCTAssertEqual(RouteAlternatives.distinct([long, almost]).count, 1)
    }

    func testEmptyAndSingleRouteAreUnchanged() {
        XCTAssertTrue(RouteAlternatives.distinct([]).isEmpty)
        let one = route(600, 4_000)
        XCTAssertEqual(RouteAlternatives.distinct([one]).count, 1)
    }
}

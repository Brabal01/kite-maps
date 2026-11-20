import XCTest
@testable import VelaCore

final class RouteTrackerV26Tests: XCTestCase {
    private func route(_ line: [LatLng], seconds: Double = 100) -> Route {
        Route(mode: .drive, polyline: line, distanceMeters: Geo.length(line), typicalSeconds: seconds,
              maneuvers: [], source: "test")
    }

    func testHeadingKeepsTheArrowOnTheCorrectCarriageway() {
        // Northbound carriageway, a U-turn, then the southbound carriageway 33 m east.
        let line = [LatLng(0, 0), LatLng(0.01, 0), LatLng(0.01, 0.0003), LatLng(0, 0.0003)]
        let tracker = RouteTracker(route: route(line))
        // Closer to the southbound road, but moving north: the heading penalty must pick the north road.
        let p = tracker.update(LatLng(0.005, 0.0002), accuracy: 6, heading: 0, speed: 14)
        XCTAssertEqual(p.routeBearing, 0, accuracy: 2)
        XCTAssertLessThan(p.alongMeters, Geo.length(line) / 2 + 100)
        XCTAssertLessThan(p.offsetMeters, 30)
    }

    func testNoisyFixUsesDeadReckoningInsteadOfTeleporting() {
        let line = [LatLng(0, 0), LatLng(0.01, 0)]
        let tracker = RouteTracker(route: route(line))
        let t0 = Date()
        let first = tracker.update(LatLng(0.005, 0), accuracy: 5, heading: 0, speed: 20, now: t0)
        XCTAssertTrue(first.isPrecise)
        // 200 m east, 80 m accuracy: a bad fix beside the road, one second later.
        let second = tracker.update(LatLng(0.0052, 0.002), accuracy: 80, heading: 0, speed: 20,
                                    now: t0.addingTimeInterval(1))
        XCTAssertLessThan(second.confidence, 0.3)
        XCTAssertGreaterThan(second.alongMeters, first.alongMeters)
        XCTAssertLessThan(second.alongMeters, first.alongMeters + 80)
        XCTAssertFalse(second.offRoute, "one bad fix is not proof of leaving the route")
        XCTAssertFalse(second.isPrecise)
    }

    func testETAUsesMappedTrafficSpansNotAFlatShare() {
        let line = [LatLng(0, 0), LatLng(0.01, 0)]
        var r = route(line, seconds: 100)
        r.trafficSpans = [TrafficSpan(level: 3, startMeters: 0, lengthMeters: r.distanceMeters)]
        // Free flow is 10 m/s; a stopped span runs at a quarter of that.
        XCTAssertEqual(r.remainingSeconds(from: 0), 400, accuracy: 5)
        XCTAssertEqual(r.remainingSeconds(from: r.distanceMeters / 2), 200, accuracy: 5)
        // No mapped span: exactly the old proportional estimate.
        var clear = route(line, seconds: 100)
        clear.trafficSpans = []
        XCTAssertEqual(clear.remainingSeconds(from: clear.distanceMeters * 0.25), 75, accuracy: 0.1)
    }

    func testPoorAccuracyIsNeverPresentedAsPrecise() {
        let line = [LatLng(0, 0), LatLng(0.01, 0)]
        let tracker = RouteTracker(route: route(line))
        let p = tracker.update(LatLng(0.005, 0), accuracy: 90, heading: 0, speed: 10)
        XCTAssertFalse(p.isPrecise)
        XCTAssertFalse(p.offRoute)
    }
}

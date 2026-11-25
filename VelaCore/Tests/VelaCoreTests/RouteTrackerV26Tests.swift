import XCTest
@testable import VelaCore

final class RouteTrackerV26Tests: XCTestCase {
    private func route(_ line: [LatLng], seconds: Double = 100, mode: TravelMode = .drive) -> Route {
        Route(mode: mode, polyline: line, distanceMeters: Geo.length(line), typicalSeconds: seconds,
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

    func testWeakAccuracyStillConfirmsDepartureWithoutMatchConfidence() {
        let line = [LatLng(0, 0), LatLng(0.01, 0)]
        let tracker = RouteTracker(route: route(line))
        let start = Date()
        var progress: RouteTracker.Progress?
        // 111 m east of the road: well outside the 40 m accuracy corridor, but its map-match
        // confidence is zero because no candidate road is close.
        for i in 0..<4 {
            progress = tracker.update(LatLng(0.005, 0.001), accuracy: 40, heading: 0, speed: 10,
                                      now: start.addingTimeInterval(Double(i)))
        }
        let p = try! XCTUnwrap(progress)
        XCTAssertTrue(p.offRoute)
        XCTAssertGreaterThanOrEqual(p.offRouteFixes, 4)
        XCTAssertLessThan(p.confidence, 0.2)
        XCTAssertGreaterThanOrEqual(p.departureEvidence, 0.3)
        XCTAssertTrue(ReroutePolicy.shouldReroute(offsetMeters: p.offsetMeters, accuracy: 40,
                                                  speed: 10, offRouteFixes: p.offRouteFixes,
                                                  joinedRoute: true, nearDestination: false,
                                                  secondsSinceLast: 10,
                                                  departureEvidence: p.departureEvidence))
    }

    func testWalkReroutesAfterTwoAccurateFixesAboutTwentyMetersOffPath() {
        let line = [LatLng(0, 0), LatLng(0.01, 0)]
        let tracker = RouteTracker(route: route(line, mode: .walk))
        let now = Date()
        _ = tracker.update(LatLng(0.005, 0), accuracy: 6, speed: 1, now: now)
        let first = tracker.update(LatLng(0.005, 0.00018), accuracy: 6, speed: 1,
                                   now: now.addingTimeInterval(1))
        XCTAssertFalse(first.offRoute)
        let second = tracker.update(LatLng(0.00501, 0.00018), accuracy: 6, speed: 1,
                                    now: now.addingTimeInterval(2))
        XCTAssertTrue(second.offRoute)
        XCTAssertTrue(ReroutePolicy.shouldReroute(offsetMeters: second.offsetMeters, accuracy: 6,
                                                  speed: 1, offRouteFixes: second.offRouteFixes,
                                                  joinedRoute: true, nearDestination: false,
                                                  secondsSinceLast: 2.1,
                                                  departureEvidence: second.departureEvidence, mode: .walk))
        XCTAssertFalse(ReroutePolicy.shouldReroute(offsetMeters: second.offsetMeters, accuracy: 6,
                                                   speed: 1, offRouteFixes: second.offRouteFixes,
                                                   joinedRoute: true, nearDestination: false,
                                                   secondsSinceLast: 2.1,
                                                   departureEvidence: second.departureEvidence))
    }

    func testWalkingIgnoresSingleJumpAndRequiresThreeLessAccurateFixes() {
        let line = [LatLng(0, 0), LatLng(0.01, 0)]
        let tracker = RouteTracker(route: route(line, mode: .walk))
        let now = Date()
        let point = LatLng(0.005, 0.0007)
        XCTAssertFalse(tracker.update(point, accuracy: 6, now: now).offRoute)
        XCTAssertFalse(tracker.update(point, accuracy: 42, now: now.addingTimeInterval(1)).offRoute)
        for i in 2...4 {
            let progress = tracker.update(point, accuracy: 28, now: now.addingTimeInterval(Double(i)))
            XCTAssertEqual(progress.offRouteFixes, i - 1)
            XCTAssertEqual(progress.offRoute, i == 4)
        }
    }

    func testDeadReckoningNeverClaimsArrival() {
        let line = [LatLng(0, 0), LatLng(0.01, 0)]
        let tracker = RouteTracker(route: route(line))
        let t0 = Date()
        _ = tracker.update(LatLng(0.0098, 0), accuracy: 5, heading: 0, speed: 10, now: t0)
        // A large jump while moving: the tracker carries the last good match forward instead of
        // trusting the fix. That estimate must not be allowed to finish the trip.
        let p = tracker.update(LatLng(0.008, 0.0018), accuracy: 30, heading: 0, speed: 30,
                               now: t0.addingTimeInterval(1))
        XCTAssertTrue(p.isEstimated)
        XCTAssertFalse(p.arrived)
    }
}

import XCTest
@testable import VelaCore

final class ReroutePolicyTests: XCTestCase {
    func testPreciseConfirmedDepartureReroutes() {
        XCTAssertTrue(ReroutePolicy.shouldReroute(offsetMeters: 55, accuracy: 8, speed: 13,
                                                  offRouteFixes: 3, joinedRoute: true,
                                                  nearDestination: false, secondsSinceLast: 10,
                                                  departureEvidence: 0.7))
    }

    func testOneNoisyFixCannotStartALoop() {
        XCTAssertFalse(ReroutePolicy.shouldReroute(offsetMeters: 55, accuracy: 45, speed: 13,
                                                   offRouteFixes: 2, joinedRoute: true,
                                                   nearDestination: false, secondsSinceLast: 10,
                                                   departureEvidence: 0.4))
        XCTAssertFalse(ReroutePolicy.shouldReroute(offsetMeters: 130, accuracy: 80, speed: 13,
                                                   offRouteFixes: 6, joinedRoute: true,
                                                   nearDestination: false, secondsSinceLast: 10,
                                                   departureEvidence: 0.4))
    }

    func testCooldownAndDestinationAreRespected() {
        XCTAssertFalse(ReroutePolicy.shouldReroute(offsetMeters: 55, accuracy: 8, speed: 13,
                                                   offRouteFixes: 4, joinedRoute: true,
                                                   nearDestination: false, secondsSinceLast: 2,
                                                   departureEvidence: 0.7))
        XCTAssertFalse(ReroutePolicy.shouldReroute(offsetMeters: 55, accuracy: 8, speed: 13,
                                                   offRouteFixes: 4, joinedRoute: true,
                                                   nearDestination: true, secondsSinceLast: 10,
                                                   departureEvidence: 0.7))
    }

    func testWeakButUsableAccuracyCanStillReroute() {
        // 40 m accuracy: a genuine 100 m departure reaches the evidence threshold with three
        // confirmations. The v26 policy required four while the tracker stopped counting at three.
        XCTAssertTrue(ReroutePolicy.shouldReroute(offsetMeters: 100, accuracy: 40, speed: 10,
                                                  offRouteFixes: 3, joinedRoute: true,
                                                  nearDestination: false, secondsSinceLast: 10,
                                                  departureEvidence: 0.35))
        // 55 m needs the fourth confirmation, and the tracker must be allowed to reach four.
        XCTAssertFalse(ReroutePolicy.shouldReroute(offsetMeters: 150, accuracy: 55, speed: 10,
                                                   offRouteFixes: 3, joinedRoute: true,
                                                   nearDestination: false, secondsSinceLast: 10,
                                                   departureEvidence: 0.5))
        XCTAssertTrue(ReroutePolicy.shouldReroute(offsetMeters: 150, accuracy: 55, speed: 10,
                                                  offRouteFixes: 4, joinedRoute: true,
                                                  nearDestination: false, secondsSinceLast: 10,
                                                  departureEvidence: 0.5))
    }

    func testLowMatchConfidenceDoesNotBlockRealDeparture() {
        // Confidence near zero can mean "the fix matches no road well", which is exactly what a
        // departure looks like. Departure evidence must carry the decision instead.
        XCTAssertTrue(ReroutePolicy.shouldReroute(offsetMeters: 120, accuracy: 40, speed: 12,
                                                  offRouteFixes: 3, joinedRoute: true,
                                                  nearDestination: false, secondsSinceLast: 10,
                                                  departureEvidence: 0.45))
    }

    func testStartingInACarParkNeedsAClearDeparture() {
        // Not yet joined the route, still only 40 m to the side: the first few metres in a car
        // park must not rewrite the route every second.
        XCTAssertFalse(ReroutePolicy.shouldReroute(offsetMeters: 40, accuracy: 8, speed: 2,
                                                   offRouteFixes: 3, joinedRoute: false,
                                                   nearDestination: false, secondsSinceLast: 10,
                                                   departureEvidence: 0.7))
        XCTAssertTrue(ReroutePolicy.shouldReroute(offsetMeters: 180, accuracy: 8, speed: 8,
                                                  offRouteFixes: 3, joinedRoute: false,
                                                  nearDestination: false, secondsSinceLast: 10,
                                                  departureEvidence: 0.7))
    }
}

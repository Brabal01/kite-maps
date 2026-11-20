import XCTest
@testable import VelaCore

final class ReroutePolicyTests: XCTestCase {
    func testPreciseConfirmedDepartureReroutes() {
        XCTAssertTrue(ReroutePolicy.shouldReroute(offsetMeters: 55, accuracy: 8, speed: 13,
                                                  offRouteFixes: 3, joinedRoute: true,
                                                  nearDestination: false, secondsSinceLast: 10,
                                                  confidence: 0.7))
    }

    func testOneNoisyFixCannotStartALoop() {
        XCTAssertFalse(ReroutePolicy.shouldReroute(offsetMeters: 55, accuracy: 45, speed: 13,
                                                   offRouteFixes: 2, joinedRoute: true,
                                                   nearDestination: false, secondsSinceLast: 10,
                                                   confidence: 0.4))
        XCTAssertFalse(ReroutePolicy.shouldReroute(offsetMeters: 130, accuracy: 80, speed: 13,
                                                   offRouteFixes: 6, joinedRoute: true,
                                                   nearDestination: false, secondsSinceLast: 10,
                                                   confidence: 0.4))
    }

    func testCooldownAndDestinationAreRespected() {
        XCTAssertFalse(ReroutePolicy.shouldReroute(offsetMeters: 55, accuracy: 8, speed: 13,
                                                   offRouteFixes: 4, joinedRoute: true,
                                                   nearDestination: false, secondsSinceLast: 2,
                                                   confidence: 0.7))
        XCTAssertFalse(ReroutePolicy.shouldReroute(offsetMeters: 55, accuracy: 8, speed: 13,
                                                   offRouteFixes: 4, joinedRoute: true,
                                                   nearDestination: true, secondsSinceLast: 10,
                                                   confidence: 0.7))
    }

    func testStartingInACarParkNeedsAClearDeparture() {
        // Not yet joined the route, still only 40 m to the side: the first few metres in a car
        // park must not rewrite the route every second.
        XCTAssertFalse(ReroutePolicy.shouldReroute(offsetMeters: 40, accuracy: 8, speed: 2,
                                                   offRouteFixes: 3, joinedRoute: false,
                                                   nearDestination: false, secondsSinceLast: 10,
                                                   confidence: 0.7))
        XCTAssertTrue(ReroutePolicy.shouldReroute(offsetMeters: 180, accuracy: 8, speed: 8,
                                                  offRouteFixes: 3, joinedRoute: false,
                                                  nearDestination: false, secondsSinceLast: 10,
                                                  confidence: 0.7))
    }
}

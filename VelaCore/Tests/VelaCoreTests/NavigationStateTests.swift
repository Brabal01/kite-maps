import XCTest
@testable import VelaCore

final class NavigationStateTests: XCTestCase {
    private func started() -> NavigationSessionState {
        var s = NavigationSessionState()
        _ = s.send(.started)
        _ = s.send(.awaitingFirstFix)
        return s
    }

    func testLifecycleFromFirstFixToArrival() {
        var s = started()
        XCTAssertEqual(s.state, .waitingForGPS)
        XCTAssertEqual(s.send(.firstFix), .navigating)
        XCTAssertEqual(s.send(.approachingArrival), .arriving)
        XCTAssertEqual(s.send(.arrived), .arrived)
        XCTAssertFalse(s.state.isActive)
    }

    func testEndedSessionIgnoresEveryLateEvent() {
        var s = NavigationSessionState(id: UUID(), state: .navigating)
        _ = s.send(.ended)
        XCTAssertEqual(s.state, .ended)
        for event in [NavigationEvent.firstFix, .leftRoute, .rerouteRequested, .rerouteSucceeded, .arrived] {
            _ = s.send(event)
            XCTAssertEqual(s.state, .ended)
        }
    }

    func testGpsLossKeepsTheStateToReturnTo() {
        var s = NavigationSessionState(state: .navigating)
        XCTAssertEqual(s.send(.gpsLost), .gpsLost)
        XCTAssertEqual(s.send(.gpsRecovered), .navigating)

        _ = s.send(.leftRoute)
        XCTAssertEqual(s.state, .offRoute)
        _ = s.send(.gpsLost)
        XCTAssertEqual(s.state, .gpsLost)
        XCTAssertEqual(s.send(.gpsRecovered), .offRoute)
    }

    func testRerouteLifecycleCannotProduceImpossibleCombinations() {
        var s = NavigationSessionState(state: .navigating)
        XCTAssertEqual(s.send(.rerouteRequested), .rerouting)
        XCTAssertEqual(s.send(.rerouteFailed), .rerouteUnavailable)
        XCTAssertEqual(s.send(.returnedToRoute), .routeRecovered)
        XCTAssertEqual(s.send(.firstFix), .navigating)

        _ = s.send(.leftRoute)
        _ = s.send(.rerouteRequested)
        XCTAssertEqual(s.send(.rerouteSucceeded), .navigating)
        // Arriving while a reroute is loading is not allowed to set both.
        XCTAssertEqual(s.send(.rerouteSucceeded), .navigating)
    }

    func testArrivalDuringRerouteEndsAsArrivedOnlyAfterAValidTransition() {
        var s = NavigationSessionState(state: .rerouting)
        XCTAssertEqual(s.send(.arrived), .rerouting)
        XCTAssertEqual(s.send(.rerouteSucceeded), .navigating)
        XCTAssertEqual(s.send(.arrived), .arrived)
    }

    func testUpdateFromNavigatorBooleans() {
        var s = NavigationSessionState()
        XCTAssertEqual(s.update(hasProgress: false, arrived: false, rerouting: false,
                                gpsLost: false, estimating: false, offRoute: false,
                                remainingMeters: nil), .waitingForGPS)
        XCTAssertEqual(s.update(hasProgress: true, arrived: false, rerouting: false,
                                gpsLost: false, estimating: false, offRoute: false,
                                remainingMeters: 900), .navigating)
        XCTAssertEqual(s.update(hasProgress: true, arrived: false, rerouting: true,
                                gpsLost: false, estimating: false, offRoute: true,
                                remainingMeters: 400), .rerouting)
        XCTAssertEqual(s.update(hasProgress: true, arrived: false, rerouting: false,
                                gpsLost: false, estimating: true, offRoute: true,
                                remainingMeters: 300), .gpsUncertain)
        XCTAssertEqual(s.update(hasProgress: true, arrived: false, rerouting: false,
                                gpsLost: true, estimating: false, offRoute: true,
                                remainingMeters: 300), .gpsLost)
        // A missing fix cannot prove arrival; the state stays honest.
        XCTAssertEqual(s.update(hasProgress: true, arrived: true, rerouting: false,
                                gpsLost: true, estimating: false, offRoute: true,
                                remainingMeters: 0), .gpsLost)

        var arrival = NavigationSessionState(state: .navigating)
        XCTAssertEqual(arrival.update(hasProgress: true, arrived: true, rerouting: false,
                                      gpsLost: false, estimating: false, offRoute: false,
                                      remainingMeters: 0), .arrived)
    }

    func testTwoSessionsNeverShareIdentityOrTransitions() {
        var a = NavigationSessionState(state: .navigating)
        var b = NavigationSessionState(state: .navigating)
        XCTAssertNotEqual(a.id, b.id)
        _ = a.send(.ended)
        _ = b.send(.leftRoute)
        XCTAssertEqual(a.state, .ended)
        XCTAssertEqual(b.state, .offRoute)
    }
}

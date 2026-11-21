import XCTest
@testable import VelaCore

final class ControlDisplayPolicyTests: XCTestCase {
    private func c(_ kind: RouteControl.Kind) -> RouteControl {
        RouteControl(kind: kind, location: LatLng(50, -1))
    }

    func testDrivingShowsTheJunctionAheadAndHidesCrossStreetFurniture() {
        XCTAssertTrue(ControlDisplayPolicy.shouldShow(c(.light), activity: .navigatingDrive, distanceAhead: 180))
        XCTAssertFalse(ControlDisplayPolicy.shouldShow(c(.light), activity: .navigatingDrive, distanceAhead: 900))
        XCTAssertFalse(ControlDisplayPolicy.shouldShow(c(.crossing), activity: .navigatingDrive, distanceAhead: 30))
        XCTAssertFalse(ControlDisplayPolicy.shouldShow(c(.oneWay), activity: .navigatingDrive, distanceAhead: 30))
        XCTAssertTrue(ControlDisplayPolicy.shouldShow(c(.yield), activity: .navigatingDrive, distanceAhead: 120))
    }

    func testUnknownDirectionIsNotPresentedAsOurLight() {
        XCTAssertFalse(ControlDisplayPolicy.shouldShow(c(.light), activity: .navigatingDrive,
                                                       distanceAhead: 80, directionCertain: false))
    }

    func testWalkingPrefersCrossingsAndHidesCarOnlyFurniture() {
        XCTAssertTrue(ControlDisplayPolicy.shouldShow(c(.crossing), activity: .navigatingWalk, distanceAhead: 40))
        XCTAssertFalse(ControlDisplayPolicy.shouldShow(c(.stop), activity: .navigatingWalk, distanceAhead: 40))
        XCTAssertFalse(ControlDisplayPolicy.shouldShow(c(.oneWay), activity: .navigatingWalk, distanceAhead: 40))
    }

    func testBrowsingKeepsMoreContext() {
        XCTAssertTrue(ControlDisplayPolicy.shouldShow(c(.crossing), activity: .browsing, distanceAhead: 2000))
        XCTAssertTrue(ControlDisplayPolicy.shouldShow(c(.light), activity: .browsing, distanceAhead: 2000))
    }

    func testUpcomingKeepsRouteOrderAndLimit() {
        let line = [LatLng(50, -1), LatLng(50, -0.99)]
        let controls = [
            RouteControl(kind: .light, location: LatLng(50, -0.9985)),
            RouteControl(kind: .stop, location: LatLng(50, -0.999)),
            RouteControl(kind: .crossing, location: LatLng(50, -0.997))
        ]
        let upcoming = ControlDisplayPolicy.upcoming(controls, along: line,
                                                     activity: .navigatingDrive, limit: 2)
        XCTAssertEqual(upcoming.map(\.kind), [.stop, .light])
    }
}

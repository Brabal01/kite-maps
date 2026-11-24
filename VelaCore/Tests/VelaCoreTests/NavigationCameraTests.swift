import XCTest
@testable import VelaCore

final class NavigationCameraTests: XCTestCase {
    func testGpsReplayFromCachedPositionThroughAccurateFix() {
        let cached = LatLng(49.592, 17.252)
        let firstPrecise = LatLng(49.604, 17.263)
        XCTAssertFalse(NavigationCamera.reliableFix(age: 90, accuracy: 8))
        XCTAssertFalse(NavigationCamera.reliableFix(age: 0.6, accuracy: 1000))
        let reliable = NavigationCamera.reliableFix(age: 0.6, accuracy: 8)
        XCTAssertTrue(reliable)
        XCTAssertTrue(NavigationCamera.reanchor(firstReliableFix: reliable,
                                               displacement: cached.distance(to: firstPrecise), accuracy: 8))
        XCTAssertFalse(NavigationCamera.reanchor(firstReliableFix: false, displacement: 1100, accuracy: 8))
        XCTAssertFalse(NavigationCamera.reanchor(firstReliableFix: true, displacement: 16, accuracy: 15))
    }

    func testCloseStartAndRepeatedLocationTapWhileStationary() {
        var controls = NavigationCamera.FollowControls()
        let point = LatLng(49.592, 17.252)
        controls.begin(at: 100)
        XCTAssertEqual(controls.distance(700, scale: 1, mode: .drive, at: 109), 350)
        XCTAssertEqual(controls.distance(700, scale: 1, mode: .drive, at: 110), 700)
        XCTAssertEqual(controls.distance(135, scale: 1, mode: .walk, at: 109), 135)
        controls.tapLocation(point, following: false, at: 200)
        XCTAssertEqual(controls.zoomSteps, 0)
        controls.tapLocation(point, following: true, at: 280)
        XCTAssertEqual(controls.zoomSteps, 5)
        XCTAssertLessThan(controls.distance(700, scale: 1, mode: .drive, at: 280), 80)
        controls.begin(at: 300)
        XCTAssertEqual(controls.zoomSteps, 0)
    }

    func testWalkUsesSmallerSnapRadiusAndRejectsOffRoutePositions() {
        XCTAssertTrue(NavigationCamera.snappedToRoute(mode: .drive, offset: 25, offRoute: false))
        XCTAssertFalse(NavigationCamera.snappedToRoute(mode: .walk, offset: 25, offRoute: false))
        XCTAssertFalse(NavigationCamera.snappedToRoute(mode: .drive, offset: 5, offRoute: true))
    }

    func testShortViewportAndHeadingAcrossNorth() {
        for height in [160.0, 320, 480, 499, 500, 540, 567, 800] {
            let padding = NavigationCamera.padding(height: height)
            XCTAssertGreaterThanOrEqual(height - padding.top - padding.bottom + 0.0001, 48)
        }
        XCTAssertEqual(NavigationCamera.shortestTurn(from: 350, to: 18), 28)
        XCTAssertEqual(NavigationCamera.shortestTurn(from: 18, to: 350), -28)
    }
}

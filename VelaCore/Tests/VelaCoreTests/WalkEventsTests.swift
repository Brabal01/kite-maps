import XCTest
@testable import VelaCore

final class WalkEventsTests: XCTestCase {
    private let line = [LatLng(0, 0), LatLng(0.01, 0)]

    func testOneWayCrossingMustSharePedestrianNode() {
        let road: [String: Any] = ["type": "way", "tags": ["highway": "residential", "oneway": "-1"],
            "nodes": [Int64(1), 2, 3], "geometry": [["lat": 0.005, "lon": -0.001],
                ["lat": 0.005, "lon": 0.0], ["lat": 0.005, "lon": 0.001]]]
        let path: [String: Any] = ["type": "way", "tags": ["highway": "footway"], "nodes": [Int64(4), 2, 5]]
        let cumulative = Geo.cumulative(line)
        XCTAssertTrue(RouteControls.mapped([road], on: line, cumulative: cumulative, walking: true).isEmpty)
        XCTAssertEqual(RouteControls.mapped([road, path], on: line, cumulative: cumulative, walking: true).map(\.kind), [.oneWay])
        XCTAssertTrue(RouteControls.mapped([road, path], on: line, cumulative: cumulative).isEmpty)
    }

    func testWalkShowsStopFacingVehiclesInOppositeDirection() {
        let stop: [String: Any] = ["type": "node", "id": Int64(1), "lat": 0.005, "lon": 0.0,
                                  "tags": ["highway": "stop", "direction": "backward"]]
        let cumulative = Geo.cumulative(line)
        XCTAssertTrue(RouteControls.mapped([stop], on: line, cumulative: cumulative).isEmpty)
        XCTAssertEqual(RouteControls.mapped([stop], on: line, cumulative: cumulative, walking: true).map(\.kind), [.stop])
    }
}

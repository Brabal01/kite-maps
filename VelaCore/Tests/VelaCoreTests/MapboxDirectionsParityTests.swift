import XCTest
@testable import VelaCore

final class MapboxDirectionsParityTests: XCTestCase {
    private let fixture = """
    {"code":"Ok","routes":[{
      "geometry":"??o}@?o}@?o}@?","distance":333.6,"duration":45,"duration_typical":40,
      "legs":[
        {"annotation":{"congestion":["low"],"maxspeed":[{"speed":30,"unit":"mph"}]},"steps":[
          {"name":"First Road","distance":111.2,"maneuver":{"type":"depart","location":[0,0]}},
          {"distance":0,"maneuver":{"type":"arrive","location":[0,0.001]}}]},
        {"annotation":{"congestion":["heavy","heavy"],"maxspeed":[{"speed":30,"unit":"mph"},{"unknown":true}]},"steps":[
          {"name":"First Road","distance":111.2,"maneuver":{"type":"depart","location":[0,0.001]}},
          {"name":"Second Road","distance":111.2,"maneuver":{"type":"turn","modifier":"left","location":[0,0.002],"instruction":"Bear left onto Second Road"},
           "intersections":[{"lanes":[{"indications":["left"],"valid":true},{"indications":["straight"],"valid":false}]}]},
          {"distance":0,"maneuver":{"type":"arrive","location":[0,0.003]}}]}
      ]}]}
    """

    func testAnnotationsAndManeuversAcrossStops() throws {
        let route = try XCTUnwrap(MapboxRoutes.parse(Data(fixture.utf8), mode: .drive).first)
        XCTAssertEqual(route.source, "mapbox")
        XCTAssertEqual(route.durationSeconds, 45)
        XCTAssertEqual(route.typicalSeconds, 40)
        XCTAssertEqual(route.maneuvers.map(\.type), [.depart, .turnLeft, .arrive])
        XCTAssertEqual(route.maneuvers[1].instruction, "Bear left onto Second Road")
        XCTAssertEqual(route.maneuvers[1].lanes.map(\.valid), [true, false])
        XCTAssertEqual(route.speedLimits.first?.kmh ?? 0, 30 * 1.609344, accuracy: 0.0001)
        XCTAssertNil(route.speedLimits.last?.kmh)
        let span = try XCTUnwrap(route.trafficSpans.first)
        XCTAssertEqual(span.startMeters, 111.2, accuracy: 1)
        XCTAssertEqual(span.lengthMeters, 222.4, accuracy: 1)
    }

    func testTrafficRefreshKeepsOriginalRouteAndRejectsParallelRoad() throws {
        var fresh = try XCTUnwrap(MapboxRoutes.parse(Data(fixture.utf8), mode: .drive).first)
        let route = [LatLng(-0.003, 0), LatLng(0, 0), LatLng(0.008, 0)]
        let from = Geo.length(Array(route.prefix(2)))
        let old = [TrafficSpan(level: 1, startMeters: 0, lengthMeters: 85),
                   TrafficSpan(level: 1, startMeters: 920, lengthMeters: 40)]
        let spans = try XCTUnwrap(MapboxRoutes.refreshedTraffic(line: route, previous: old, fresh: fresh, from: from))
        XCTAssertEqual(spans.map(\.level), [1, 2, 1])
        XCTAssertEqual(spans[1].startMeters, from + 111.2, accuracy: 1)
        fresh.polyline = fresh.polyline.map { LatLng($0.lat, $0.lng + 0.0004) }
        XCTAssertNil(MapboxRoutes.refreshedTraffic(line: route, previous: old, fresh: fresh, from: from))
    }
}

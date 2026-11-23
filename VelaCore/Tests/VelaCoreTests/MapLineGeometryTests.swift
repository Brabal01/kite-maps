import XCTest
@testable import VelaCore

final class MapLineGeometryTests: XCTestCase {
    func testInvalidPointAndLongGapDoNotJoinSurvivingSegments() {
        let a = LatLng(49.590, 17.265), b = LatLng(49.591, 17.266)
        let c = LatLng(49.605, 17.285), d = LatLng(49.606, 17.286)
        let gap = LatLng(17.266, .nan)
        XCTAssertEqual(MapLineGeometry.segments([a, a, b, gap, c, d]), [[a, b], [c, d]])
        XCTAssertEqual(MapLineGeometry.segments([a, b, c, d], maximumEdgeMeters: 1_000), [[a, b], [c, d]])
    }

    func testDateLineSplitInBothDirections() {
        let a = LatLng(10, 179), b = LatLng(12, -179)
        let east = LatLng(11, 180), west = LatLng(11, -180)
        XCTAssertEqual(MapLineGeometry.segments([a, b]), [[a, east], [west, b]])
        XCTAssertEqual(MapLineGeometry.segments([b, a]), [[b, west], [east, a]])
    }

    func testTruncatedPolylineDoesNotRenderValidPrefix() {
        XCTAssertFalse(Geo.decodePolyline("optmHonjhBgEgE_DkH", precision: 1e5).isEmpty)
        XCTAssertTrue(Geo.decodePolyline("optmHonjhBgEgE_DkH_", precision: 1e5).isEmpty)
        XCTAssertTrue(Geo.decodePolyline("optmHonjhBgEgE_DkH ", precision: 1e5).isEmpty)
        XCTAssertTrue(Geo.decodePolyline(String(repeating: "_", count: 90)).isEmpty)
    }

    func testTransitLayerDoesNotLeakIntoRoadGuidance() {
        for requested in [false, true] {
            XCTAssertFalse(MapLayerPolicy.showsTransitNetwork(requested: requested, activeTransit: false,
                                                               planningTransit: false, roadGuidance: true))
        }
        XCTAssertTrue(MapLayerPolicy.showsTransitNetwork(requested: false, activeTransit: true,
                                                          planningTransit: false, roadGuidance: false))
        XCTAssertTrue(MapLayerPolicy.showsTransitNetwork(requested: false, activeTransit: false,
                                                          planningTransit: true, roadGuidance: false))
        XCTAssertFalse(MapLayerPolicy.showsTransitNetwork(requested: false, activeTransit: false,
                                                           planningTransit: false, roadGuidance: false))
    }

    func testStreetTransitChordIsSplitBeforeColoring() throws {
        // Synthetic geometry around the třída Kosmonautů corridor. The middle
        // edge spans about 2 km, like a multi-point chord in the live response.
        let payload = #"{"routes":[{"mode":"BUS","transitRoutes":[{"color":"FF0000"}]}],"polylines":[{"polyline":{"points":"optmHonjhB_DgEwwAohCsDkH","precision":5},"routeIndexes":[0]}]}"#
        let lines = Transitous.parseLines(Data(payload.utf8), includeBuses: true)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines.allSatisfy { $0.points.count == 2 && $0.color == 0xFF0000 })
        for line in lines { XCTAssertLessThan(Geo.length(line.points), 300) }
    }

    func testRefreshedTrafficDoesNotJumpAcrossParallelRoads() throws {
        let path = [LatLng(49.59, 17.25), LatLng(49.59, 17.26)]
        let span = TrafficSpan(level: 2, startMeters: 100, lengthMeters: 180)
        var route = Route(mode: .drive, polyline: path, distanceMeters: Geo.length(path),
                          typicalSeconds: 60, maneuvers: [], trafficSpans: [span], source: "test")
        let mapped = try XCTUnwrap(TrafficAlternatives.reprojectSpans(from: route, onto: path, startingAt: 500).first)
        XCTAssertEqual(mapped.startMeters, 600, accuracy: 2)
        XCTAssertEqual(mapped.lengthMeters, 180, accuracy: 2)
        route.polyline = path.map { LatLng($0.lat + 0.001, $0.lng) }
        XCTAssertTrue(TrafficAlternatives.reprojectSpans(from: route, onto: path, startingAt: 0).isEmpty)
    }

    func testAlternateTransitEndpointKeepsEndpointsAndArrivalTime() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let a = LatLng(35.898, 14.509), b = LatLng(35.849, 14.476)
        let url = try XCTUnwrap(Transitous.requestURL(server: "https://planner.example/region/", from: a,
                                                      to: b, time: date, arriveBy: true))
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.path, "/region/api/v2/plan")
        let query = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(query["arriveBy"], "true")
        XCTAssertEqual(query["fromPlace"], "35.898,14.509")
        XCTAssertEqual(query["toPlace"], "35.849,14.476")
        XCTAssertEqual(query["time"], ISO8601DateFormatter().string(from: date))
        XCTAssertNil(Transitous.requestURL(server: "http://planner.example", from: a, to: b))
        XCTAssertNil(Transitous.requestURL(server: "https://user:password@planner.example", from: a, to: b))
    }
}

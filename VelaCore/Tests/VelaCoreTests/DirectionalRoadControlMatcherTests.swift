import XCTest
@testable import VelaCore

final class DirectionalRoadControlMatcherTests: XCTestCase {
    let origin = LatLng(50, -1)
    var kLng: Double { 111_320 * cos(origin.lat * .pi / 180) }

    func p(_ east: Double, _ north: Double) -> LatLng {
        LatLng(origin.lat + north / 110_540, origin.lng + east / kLng)
    }

    func node(_ id: Int64, _ east: Double, _ north: Double, _ tags: [String: String] = [:]) -> [String: Any] {
        let q = p(east, north)
        return ["type": "node", "id": id, "lat": q.lat, "lon": q.lng, "tags": tags]
    }

    func way(_ id: Int64, _ nodes: [Int64], _ pts: [(Double, Double)], _ tags: [String: String]) -> [String: Any] {
        let geometry = pts.map { q -> [String: Any] in
            let c = p(q.0, q.1)
            return ["lat": c.lat, "lon": c.lng]
        }
        return ["type": "way", "id": id, "nodes": nodes.map { NSNumber(value: $0) }, "geometry": geometry, "tags": tags]
    }

    func mainRoad(id: Int64 = 10, east: Bool = true) -> [String: Any] {
        way(id, [1, 2, 3, 4], [(0, 0), (100, 0), (150, 0), (200, 0)], ["highway": "residential", "name": "Main Street"])
    }

    func route(_ pts: [(Double, Double)]) -> ([LatLng], [Double]) {
        let line = pts.map { p($0.0, $0.1) }
        return (line, Geo.cumulative(line))
    }

    func match(_ elements: [[String: Any]], _ pts: [(Double, Double)] = [(0, 0), (200, 0)]) -> [RouteControl] {
        let r = route(pts)
        return DirectionalRoadControlMatcher.match(elements: elements, on: r.0, cumulative: r.1)
    }

    func testSignalOnOurRoadIsShownWithRouteDistance() throws {
        let controls = match([mainRoad(), node(2, 100, 0, ["highway": "traffic_signals"])])
        let c = try XCTUnwrap(controls.first)
        XCTAssertEqual(controls.count, 1)
        XCTAssertEqual(c.kind, .light)
        XCTAssertEqual(try XCTUnwrap(c.alongMeters), 100, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(c.offsetMeters), 0, accuracy: 1)
        XCTAssertEqual(c.wayID, 10)
        XCTAssertEqual(c.osmID, 2)
        XCTAssertTrue(c.directionCertain)
        XCTAssertEqual(c.relevance, .relevant)
        XCTAssertTrue(ControlDisplayPolicy.shouldShow(c, activity: .navigatingDrive, distanceAhead: 100,
                                                      directionCertain: c.directionCertain))
    }

    func testSignalOnOppositeCarriagewayIsNotOurs() throws {
        let opposite = way(11, [5, 6, 7], [(200, 8), (150, 8), (0, 8)],
                           ["highway": "residential", "oneway": "yes", "name": "Main Street"])
        let controls = match([mainRoad(), opposite, node(6, 150, 8, ["highway": "traffic_signals"])])
        let c = try XCTUnwrap(controls.first)
        XCTAssertFalse(c.directionCertain)
        XCTAssertNotEqual(c.relevance, .relevant)
        XCTAssertFalse(ControlDisplayPolicy.shouldShow(c, activity: .navigatingDrive, distanceAhead: 150,
                                                       directionCertain: c.directionCertain))
    }

    func testSignalOnCrossingRoadIsNotOurs() throws {
        let cross = way(12, [8, 9, 10], [(100, -20), (100, 6), (100, 20)],
                        ["highway": "secondary", "name": "Cross Road"])
        let controls = match([mainRoad(), cross, node(9, 100, 6, ["highway": "traffic_signals"])])
        let c = try XCTUnwrap(controls.first)
        XCTAssertFalse(c.directionCertain)
        XCTAssertEqual(c.relevance, .ambiguous)
        XCTAssertFalse(ControlDisplayPolicy.shouldShow(c, activity: .navigatingDrive, distanceAhead: 100,
                                                       directionCertain: c.directionCertain))
    }

    func testTwoSeparateSignalisedJunctionsTwentyMetresApartBothStay() {
        let road = way(10, [1, 2, 3, 4], [(0, 0), (100, 0), (120, 0), (200, 0)],
                       ["highway": "residential"])
        let controls = match([road,
                              node(2, 100, 0, ["highway": "traffic_signals"]),
                              node(3, 120, 0, ["highway": "traffic_signals"])])
        XCTAssertEqual(controls.count, 2, "two junctions 20 m apart must not merge")
        XCTAssertEqual(controls.map { Int(($0.alongMeters ?? 0).rounded()) }, [100, 120])
    }

    func testTwoHeadsOnOneStopLineAreOne() {
        let road = way(10, [1, 2, 3, 4], [(0, 0), (100, 0), (106, 0), (200, 0)],
                       ["highway": "residential"])
        let controls = match([road,
                              node(2, 100, 0, ["highway": "traffic_signals"]),
                              node(3, 106, 0, ["highway": "traffic_signals"])])
        XCTAssertEqual(controls.count, 1)
    }

    func testTurnLaneSignalBelongsToTheLaneYouTake() throws {
        let slip = way(13, [20, 21, 22], [(100, 0), (120, 4), (170, 9)],
                       ["highway": "primary", "name": "Slip Road"])
        let signal = node(21, 120, 4, ["highway": "traffic_signals"])
        let straight = match([mainRoad(), slip, signal])
        let sc = try XCTUnwrap(straight.first)
        XCTAssertNotEqual(sc.relevance, .relevant, "a turn-lane signal is not ours when we go straight")
        XCTAssertFalse(ControlDisplayPolicy.shouldShow(sc, activity: .navigatingDrive, distanceAhead: 120,
                                                       directionCertain: sc.directionCertain))

        let turning = match([mainRoad(), slip, signal], [(0, 0), (100, 0), (120, 4), (170, 9), (200, 9)])
        let tc = try XCTUnwrap(turning.first)
        XCTAssertEqual(tc.relevance, .relevant)
        XCTAssertTrue(tc.directionCertain)
    }

    func testSignalOnAnOverpassIsNotTheRoadBelow() throws {
        let bridge = way(14, [30, 31], [(60, 10), (140, 10)],
                         ["highway": "primary", "bridge": "yes", "layer": "1"])
        let controls = match([mainRoad(), bridge, node(30, 60, 10, ["highway": "traffic_signals"])])
        let c = try XCTUnwrap(controls.first)
        XCTAssertNotEqual(c.relevance, .relevant)
    }

    func testSignalUnderABridgeOnOurRoadStays() throws {
        let under = way(15, [40, 41, 42], [(0, 0), (100, 0), (200, 0)],
                        ["highway": "primary", "tunnel": "yes", "layer": "-1"])
        let over = way(16, [43, 44], [(60, 8), (140, 8)],
                       ["highway": "primary", "bridge": "yes", "layer": "1"])
        let controls = match([under, over, node(41, 100, 0, ["highway": "traffic_signals"])])
        let c = try XCTUnwrap(controls.first)
        XCTAssertEqual(c.relevance, .relevant)
        XCTAssertEqual(c.wayID, 15)
    }

    func testOneWayJunctionShowsOnlyOurApproach() throws {
        let ours = way(17, [50, 51, 52], [(0, 0), (100, 0), (200, 0)],
                       ["highway": "primary", "oneway": "yes"])
        let cross = way(18, [51, 53], [(100, 0), (100, 60)],
                        ["highway": "primary", "oneway": "yes"])
        let controls = match([ours, cross,
                              node(51, 100, 0, ["highway": "traffic_signals"]),
                              node(53, 100, 10, ["highway": "traffic_signals"])])
        let relevant = controls.filter { $0.relevance == .relevant }
        XCTAssertEqual(relevant.count, 1)
        XCTAssertEqual(try XCTUnwrap(relevant.first?.alongMeters), 100, accuracy: 1)
        XCTAssertEqual(controls.count, 2, "the cross street's head is context, not ours")
    }

    func testMissingDirectionTagsStillShowOurRoadSignal() throws {
        let controls = match([mainRoad(), node(2, 100, 0, ["highway": "traffic_signals"])])
        let c = try XCTUnwrap(controls.first)
        XCTAssertEqual(c.relevance, .relevant)
        XCTAssertGreaterThanOrEqual(c.confidence, 0.85)
        XCTAssertTrue(c.directionCertain)
    }

    func testReversedTravelOnTheSameRoad() throws {
        let road = way(19, [60, 61, 62], [(0, 0), (100, 0), (200, 0)],
                       ["highway": "primary", "name": "Main"])
        let signal = node(61, 100, 0, ["highway": "traffic_signals", "traffic_signals:direction": "forward"])
        let east = match([road, signal])
        XCTAssertEqual(east.first?.relevance, .relevant)

        // Going west, the same head faces away from us.
        let west = match([road, signal], [(200, 0), (0, 0)])
        XCTAssertTrue(west.isEmpty, "a forward-facing head is not ours when we travel against the way")
    }

    func testFastRouteChangeDropsOldControls() {
        let road = way(10, [1, 2, 3, 4], [(0, 0), (100, 0), (150, 0), (200, 0)], ["highway": "residential"])
        let signal = node(2, 100, 0, ["highway": "traffic_signals"])
        XCTAssertEqual(match([road, signal]).count, 1)
        // The new route is 5 km away: the old junction must not follow it.
        XCTAssertTrue(match([road, signal], [(0, 5000), (200, 5000)]).isEmpty)
    }

    func testSignalBehindTheVehicleIsNotUpcoming() {
        let c = RouteControl(kind: .light, location: p(100, 0), alongMeters: 100)
        XCTAssertFalse(ControlDisplayPolicy.shouldShow(c, activity: .navigatingDrive, distanceAhead: -50))
    }

    func testParallelRoadSignalIsNotOurs() throws {
        let parallel = way(20, [70, 71, 72], [(0, 8), (100, 8), (200, 8)],
                           ["highway": "residential", "name": "Back Lane"])
        let controls = match([mainRoad(), parallel, node(71, 100, 8, ["highway": "traffic_signals"])])
        let c = try XCTUnwrap(controls.first)
        XCTAssertNotEqual(c.relevance, .relevant)
        XCTAssertFalse(ControlDisplayPolicy.shouldShow(c, activity: .navigatingDrive, distanceAhead: 100,
                                                       directionCertain: c.directionCertain))
    }

    func testMissingOverpassAnswerMeansNoControls() {
        XCTAssertTrue(match([]).isEmpty)
    }

    func testPostpassNodeWithoutGeometryStillCountsOnTheLine() throws {
        let controls = match([node(80, 100, 0, ["highway": "traffic_signals"])])
        let c = try XCTUnwrap(controls.first)
        XCTAssertEqual(c.kind, .light)
        XCTAssertEqual(c.relevance, .relevant)
        XCTAssertEqual(c.source, "osm")
        XCTAssertTrue(ControlDisplayPolicy.shouldShow(c, activity: .navigatingDrive, distanceAhead: 100,
                                                      directionCertain: c.directionCertain))
    }

    func testDuplicateNodesProduceOneControl() {
        let signal = node(2, 100, 0, ["highway": "traffic_signals"])
        let controls = match([mainRoad(), signal, signal])
        XCTAssertEqual(controls.count, 1)
    }

    func testAmbiguousControlIsBrowsingOnly() throws {
        let cross = way(12, [8, 9, 10], [(100, -20), (100, 6), (100, 20)],
                        ["highway": "secondary", "name": "Cross Road"])
        let controls = match([mainRoad(), cross, node(9, 100, 6, ["highway": "traffic_signals"])])
        let c = try XCTUnwrap(controls.first)
        XCTAssertTrue(ControlDisplayPolicy.shouldShow(c, activity: .browsing, distanceAhead: 100))
        XCTAssertFalse(ControlDisplayPolicy.shouldShow(c, activity: .navigatingDrive, distanceAhead: 100,
                                                       directionCertain: c.directionCertain))
    }

    func testStopAndCrossingKeepTheirOwnReach() throws {
        let controls = match([mainRoad(),
                              node(90, 100, 0, ["highway": "stop"]),
                              node(91, 140, 0, ["highway": "crossing"])])
        XCTAssertEqual(controls.map(\.kind), [.stop, .crossing])
        XCTAssertEqual(controls.map { Int(($0.alongMeters ?? 0).rounded()) }, [100, 140])
    }
}

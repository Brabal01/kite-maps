import XCTest
@testable import VelaCore

/**
 * Golden fixture: the real roundabout at the northern end of Vejdovského street, Olomouc (Hodolany),
 * fetched from OpenStreetMap. It is an irregular, fragmented seven-way ring with dual-carriageway and
 * one-way arms (service roads, a residential branch and the Vejdovského route through it).
 *
 * The drive that exposed the bug: approach from the south-west on Vejdovského (way 1344866047), travel
 * counter-clockwise (right-hand traffic) and leave on Vejdovského to the north-east (way 1344866048).
 * The router said "1st exit" but the route really takes the 2nd (the first arm after the way in is
 * service/residential, not usable as the Vejdovského continuation). The resolver, given the mapped
 * topology, must say 2 — and a route that genuinely takes the first arm must still say 1.
 */
final class OlomoucRoundaboutTests: XCTestCase {
    let center = LatLng(49.5882409, 17.2705156)

    private func ways() throws -> [Roundabouts.Way] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/olomouc_vejdovskeho_roundabout.json")
        let data = try Data(contentsOf: url)
        return Roundabouts.parse(data)
    }

    /// A path that reaches the entry way's first node and then arcs counter-clockwise (right-hand
    /// traffic in the Czech Republic) to the given exit arm's first point.
    private func makeRoute(entry: LatLng, exit: LatLng) -> (line: [LatLng], cum: [Double], along: Double, exitPoint: LatLng) {
        func b(_ p: LatLng) -> Double {
            let dlat = p.lat - center.lat, dlon = (p.lng - center.lng) * cos(center.lat * .pi / 180)
            return atan2(dlon, dlat) * 180 / .pi
        }
        func pt(_ deg: Double) -> LatLng {
            LatLng(center.lat + 11 * cos(deg * .pi / 180) / 110_540,
                   center.lng + 11 * sin(deg * .pi / 180) / (111_320 * cos(center.lat * .pi / 180)))
        }
        let eb = b(entry), xb = b(exit)
        var line: [LatLng] = [pt(eb - 180), pt(eb - 100), pt(eb - 10), entry]
        var d = eb - 8
        // counter-clockwise (right-hand traffic): bearings decrease as we go round
        while d > xb { line.append(pt(d)); d -= 8 }
        line.append(exit)
        let cum = Geo.cumulative(line)
        let along = cum[3]
        return (line, cum, along, exit)
    }

    func testVejdovskoeRouteThroughTakesSecondNotFirst() throws {
        let ways = try ways()
        let entryWay = ways.first { $0.id == 1344866047 }! // south-west approach
        let exitWay = ways.first { $0.id == 1344866048 }!  // north-east continuation
        let route = makeRoute(entry: entryWay.points.first!, exit: exitWay.points.first!)
        XCTAssertLessThan(route.exitPoint.distance(to: exitWay.points.first!), 0.1)

        // The router got it wrong.
        let evil = RoundaboutExitResolver.resolve(RoundaboutExitEvidence(
            entry: entryWay.points.first!, exitPoint: exitWay.points.first!, line: route.line,
            cumulative: route.cum, along: route.along, clockwise: false, routerExit: 1,
            googleExit: nil, ways: ways))
        XCTAssertEqual(evil.exit, 2, "West, north, east: the Vejdovského continuation is the 2nd exit")
        XCTAssertEqual(evil.osmExit, 2)
        XCTAssertEqual(evil.source, .osmTopology)
        XCTAssertTrue(evil.isCertain)
        XCTAssertEqual(evil.eligibleExits, 3)

        // The correct router number agrees.
        let good = RoundaboutExitResolver.resolve(RoundaboutExitEvidence(
            entry: entryWay.points.first!, exitPoint: exitWay.points.first!, line: route.line,
            cumulative: route.cum, along: route.along, clockwise: false, routerExit: 2,
            googleExit: nil, ways: ways))
        XCTAssertEqual(good.exit, 2)
        XCTAssertEqual(good.source, .routerCorroborated)
        XCTAssertGreaterThan(good.confidence, evil.confidence)
    }

    func testVejdovskoeFirstArmIsStillFirst() throws {
        let ways = try ways()
        let entryWay = ways.first { $0.id == 1344866047 }!
        // The very first arm after the way in, going counter-clockwise, is a service road. A route
        // leaving there takes the 1st exit.
        let exitWay = ways.first { $0.id == 1344866055 }! // service
        let route = makeRoute(entry: entryWay.points.first!, exit: exitWay.points.first!)
        let r = RoundaboutExitResolver.resolve(RoundaboutExitEvidence(
            entry: entryWay.points.first!, exitPoint: exitWay.points.first!, line: route.line,
            cumulative: route.cum, along: route.along, clockwise: false, routerExit: 1,
            googleExit: nil, ways: ways))
        XCTAssertEqual(r.exit, 1)
    }

    /// Without the OSM topology a lone, unconfirmed router number is a guess, never a confirmed count.
    func testUnconfirmedRouterNumberIsNotCertain() {
        let r = RoundaboutExitResolver.withoutTopology(router: 1, google: nil, reason: "no map")
        XCTAssertEqual(r.exit, 1)
        XCTAssertEqual(r.source, .router)
        XCTAssertFalse(r.isCertain, "a single router number with no map is only a guess")
        XCTAssertEqual(r.confidence, 0.55)
    }

    /// V36 §3.7: when a roundabout's number is not confirmed, the maneuver reads the direction, not the
    /// router's guess. Banner, diagram, voice and Live Activity all read one authoritative maneuver, so
    /// the unconfirmed number must be dropped everywhere at once.
    func testUnconfirmedNumberShowsDirectionNotAGuess() throws {
        let entry = LatLng(49.58870, 17.27046)
        let exit = LatLng(49.58779, 17.27058)
        var line = [LatLng(49.58862, 17.27086), entry]
        for d in stride(from: 0.0, through: 300, by: 20) {
            line.append(LatLng(entry.lat - d / 110_540, entry.lng + (d * 0.4) / (111_320 * cos(49.6 * .pi / 180))))
        }
        let cum = Geo.cumulative(line)
        var m = Maneuver(type: .roundabout, instruction: "At the roundabout, take the 1st exit",
                         location: entry, alongMeters: cum[1], distanceMeters: 400, exit: 1)
        m.routerExit = 1
        var off = Maneuver(type: .roundabout, instruction: "Exit the roundabout", location: exit,
                           alongMeters: cum[15], distanceMeters: 0)
        off.leavesRoundabout = true
        let route = Route(mode: .drive, polyline: line, distanceMeters: 1000, typicalSeconds: 100,
                          trafficSeconds: nil, summary: nil, maneuvers: [m, off], source: "osm")
        // No mapped ways: the resolver only has the router's unconfirmed "1st exit".
        let out = Roundabouts.resolved(route, ways: [], clockwise: false)
        XCTAssertNil(out?.maneuvers[0].exit, "no confirmed exit number may be shown")
        XCTAssertEqual(out?.maneuvers[0].routerExit, 1, "the router's guess is kept as evidence, not as the answer")
    }

    func testOsmOverridesWrongRouterWhenTopologyConfirmed() throws {
        let ways = try ways()
        let entryWay = ways.first { $0.id == 1344866047 }!
        let exitWay = ways.first { $0.id == 1344866048 }!
        let route = makeRoute(entry: entryWay.points.first!, exit: exitWay.points.first!)
        // Build a Route and run the full resolved() pipeline so the words/picture/number agree.
        var on = Maneuver(type: .roundabout, instruction: "At the roundabout, take the 1st exit",
                          location: entryWay.points.first!, alongMeters: route.along,
                          distanceMeters: 400, exit: 1)
        on.routerExit = 1
        var off = Maneuver(type: .roundabout, instruction: "Exit the roundabout",
                           location: exitWay.points.first!, alongMeters: route.along + 120, distanceMeters: 0)
        off.leavesRoundabout = true
        let routeLine = route.line
        let r = Route(mode: .drive, polyline: routeLine, distanceMeters: 1000, typicalSeconds: 100,
                      trafficSeconds: nil, summary: nil, maneuvers: [on, off], source: "osm")
        let out = try XCTUnwrap(Roundabouts.resolved(r, ways: ways, clockwise: false))
        XCTAssertEqual(out.maneuvers[0].exit, 2)
        XCTAssertEqual(out.maneuvers[0].instruction, "At the roundabout, take the 2nd exit")
        XCTAssertEqual(out.maneuvers[0].exitSource, .osmTopology)
        XCTAssertEqual(out.maneuvers[1].exit, 2, "the way off carries the same number")
    }
}
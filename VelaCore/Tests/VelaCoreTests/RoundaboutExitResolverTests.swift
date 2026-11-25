import XCTest
@testable import VelaCore

final class RoundaboutExitResolverTests: XCTestCase {
    let c = LatLng(51.5, -0.1)
    var k: Double { 111_320 * cos(c.lat * .pi / 180) }

    func at(_ deg: Double, _ r: Double) -> LatLng {
        LatLng(c.lat + r * cos(deg * .pi / 180) / 110_540, c.lng + r * sin(deg * .pi / 180) / k)
    }

    /// A four-arm roundabout: ring nodes 1…12, roads at north, east, south and west.
    func fourArm(oneWayWestIntoRing: Bool = false, splitEast: Bool = false) -> [Roundabouts.Way] {
        let ringIds: [Int64] = Array(1...12) + [1]
        let ringPts = (0..<12).map { at(Double($0) * 30, 30) } + [at(0, 30)]
        var ways = [Roundabouts.Way(id: 100, nodes: ringIds, points: ringPts,
                                    tags: ["junction": "roundabout", "highway": "primary"])]
        // Roads at north (node 1), east (4), south (7), west (10).
        for (i, deg) in [0.0, 90, 180, 270].enumerated() {
            let ringNode = Int64([1, 4, 7, 10][i])
            let tags = ["highway": "primary", "name": "Road \(i)"]
            if deg == 270, oneWayWestIntoRing {
                ways.append(Roundabouts.Way(id: 250, nodes: [50, ringNode], points: [at(270, 120), at(270, 30)],
                                            tags: tags.merging(["oneway": "yes"]) { a, _ in a }))
            } else if deg == 90, splitEast {
                // A dual carriageway: one arm out, one arm in, a few metres apart.
                ways.append(Roundabouts.Way(id: 240, nodes: [ringNode, 60], points: [at(88, 30), at(88, 120)],
                                            tags: ["highway": "primary", "name": "A27", "oneway": "yes"]))
                ways.append(Roundabouts.Way(id: 241, nodes: [61, ringNode], points: [at(92, 120), at(92, 30)],
                                            tags: ["highway": "primary", "name": "A27", "oneway": "yes"]))
            } else {
                ways.append(Roundabouts.Way(id: Int64(200 + i), nodes: [ringNode, Int64(50 + i)],
                                            points: [at(deg, 30), at(deg, 120)], tags: tags))
            }
        }
        return ways
    }

    func route(entryDeg: Double = 180, exitDeg: Double, clockwise: Bool = true) -> (line: [LatLng], cum: [Double], along: Double) {
        let raw = clockwise ? (exitDeg - entryDeg) : (entryDeg - exitDeg)
        let travel = ((raw.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
        let sweep = travel < 15 ? travel + 360 : travel
        var line = [at(entryDeg, 200), at(entryDeg, 30)]
        var d = 15.0
        while d <= sweep { line.append(at(entryDeg + (clockwise ? d : -d), 30)); d += 15 }
        line.append(at(exitDeg, 200))
        let cum = Geo.cumulative(line)
        return (line, cum, cum[1])
    }

    func resolve(ways: [Roundabouts.Way], entryDeg: Double = 180, exitDeg: Double = 90, router: Int?,
                 google: Int? = nil, clockwise: Bool = true) -> RoundaboutExitResolution {
        let r = route(entryDeg: entryDeg, exitDeg: exitDeg, clockwise: clockwise)
        return RoundaboutExitResolver.resolve(RoundaboutExitEvidence(
            entry: at(entryDeg, 30), exitPoint: at(exitDeg, 30), line: r.line, cumulative: r.cum,
            along: r.along, clockwise: clockwise, routerExit: router, googleExit: google, ways: ways))
    }

    func testTopologyCorrectsAWrongRouterNumber() {
        let r = resolve(ways: fourArm(), exitDeg: 90, router: 2)
        XCTAssertEqual(r.exit, 3, "west, north, east: the route takes the 3rd")
        XCTAssertEqual(r.osmExit, 3)
        XCTAssertEqual(r.eligibleExits, 3, "the road in is not an exit ahead")
        XCTAssertEqual(r.source, .osmTopology)
        XCTAssertTrue(r.isCertain)
        XCTAssertEqual(r.shape?.taken, 2)
        XCTAssertEqual(r.shape?.exits.count, 3)
        XCTAssertEqual(r.chosenIndex, 2)
    }

    func testGoogleRouteUsesItsOwnExitNumberWithDifferentOSMCount() throws {
        let geometry = route(exitDeg: 90)
        var step = DirectionsParser.parseStep(
            "<step maneuver='ROUNDABOUT' meters='300'>At the roundabout, take the <b>2nd</b> exit towards the centre</step>"
        )
        XCTAssertEqual(step.exit, 2, "The instruction already has a number before the OSM response")
        XCTAssertEqual(step.exitSource, .google)
        XCTAssertTrue(step.instruction.contains("towards the centre"))
        step.location = at(180, 30)
        step.alongMeters = geometry.along
        step.routerExit = 3
        var selected = Route(mode: .drive, polyline: geometry.line, distanceMeters: geometry.cum.last ?? 0,
                             typicalSeconds: 45, maneuvers: [step], source: "google")
        let enriched = try XCTUnwrap(Roundabouts.resolved(selected, ways: fourArm(), clockwise: true))
        XCTAssertEqual(enriched.maneuvers[0].exit, 2)
        XCTAssertEqual(enriched.maneuvers[0].exitSource, .google)
        XCTAssertFalse(enriched.maneuvers[0].exitAmbiguous)
        XCTAssertEqual(enriched.maneuvers[0].roundabout?.taken, 2)
        XCTAssertTrue(enriched.maneuvers[0].instruction.contains("2nd exit"))

        selected.source = "osm"
        let fallback = try XCTUnwrap(Roundabouts.resolved(selected, ways: fourArm(), clockwise: true))
        XCTAssertEqual(fallback.maneuvers[0].exit, 3)
        XCTAssertEqual(fallback.maneuvers[0].exitSource, .routerCorroborated)
    }

    func testRouterAndTopologyAgree() {
        let r = resolve(ways: fourArm(), exitDeg: 90, router: 3)
        XCTAssertEqual(r.exit, 3)
        XCTAssertEqual(r.source, .routerCorroborated)
        XCTAssertGreaterThan(r.confidence, 0.9)
    }

    func testOneWayArmIntoTheRingIsNotAnExit() {
        // West is entrance-only now, so east is the 2nd exit, not the 3rd.
        let r = resolve(ways: fourArm(oneWayWestIntoRing: true), exitDeg: 90, router: 2)
        XCTAssertEqual(r.exit, 2)
        XCTAssertEqual(r.osmExit, 2)
        XCTAssertEqual(r.source, .routerCorroborated)
    }

    func testDualCarriagewayCountsAsOneRoad() {
        let r = resolve(ways: fourArm(splitEast: true), exitDeg: 90, router: 3)
        XCTAssertEqual(r.exit, 3)
        XCTAssertEqual(r.eligibleExits, 3)
    }

    func testReverseTraversalCountsTheOtherWay() {
        let r = resolve(ways: fourArm(), entryDeg: 0, exitDeg: 180, router: 2, clockwise: true)
        // From the north, clockwise: east is 1st, south is 2nd, west 3rd.
        XCTAssertEqual(r.exit, 2)
        XCTAssertEqual(r.osmExit, 2)
    }

    func testLeftHandTrafficMirrorsTheCount() {
        let r = resolve(ways: fourArm(), exitDeg: 90, router: 1, clockwise: false)
        // Counter-clockwise from the south, east is the first arm.
        XCTAssertEqual(r.exit, 1)
    }

    func testConflictingProvidersWithoutAMapDoNotInventANumber() {
        let r = RoundaboutExitResolver.withoutTopology(router: 2, google: 4, reason: "no map")
        XCTAssertNil(r.exit)
        XCTAssertTrue(r.ambiguous)
        XCTAssertEqual(r.source, .ambiguous)
        XCTAssertFalse(r.isCertain)
    }

    func testRouterAloneIsKeptButNotCalledCertain() {
        let r = RoundaboutExitResolver.withoutTopology(router: 2, google: nil, reason: "no map")
        XCTAssertEqual(r.exit, 2)
        XCTAssertEqual(r.source, .router)
        XCTAssertFalse(r.isCertain)
        XCTAssertFalse(r.ambiguous)
    }

    func testNoEvidenceMeansNoNumber() {
        let r = RoundaboutExitResolver.withoutTopology(router: nil, google: nil, reason: "no map")
        XCTAssertNil(r.exit)
        XCTAssertEqual(r.source, .unavailable)
    }

    func testMissingBranchStillCountsWhatTheMapHas() {
        // Remove the north road: west is 1st, east is 2nd.
        let ways = fourArm().filter { $0.id != 200 }
        let r = resolve(ways: ways, exitDeg: 90, router: 2)
        XCTAssertEqual(r.exit, 2)
        XCTAssertEqual(r.eligibleExits, 2)
    }

    func testTwoExitsVeryCloseTogetherAreFlagged() {
        var ways = fourArm()
        // A service road leaving almost beside the east arm.
        ways.append(Roundabouts.Way(id: 300, nodes: [4, 90], points: [at(96, 30), at(96, 100)],
                                    tags: ["highway": "service", "name": "Service yard"]))
        let r = resolve(ways: ways, exitDeg: 90, router: 3)
        XCTAssertEqual(r.exit, 3, "the nearest arm is still the east road")
        XCTAssertTrue(r.ambiguous, "two arms 6° apart cannot be told apart with certainty")
        XCTAssertFalse(r.isCertain)
    }


    func testFiveArmRoundaboutCountsEveryLegalExit() {
        var ways = fourArm()
        // A fifth road to the north-east, between north and east.
        ways.append(Roundabouts.Way(id: 310, nodes: [2, 91], points: [at(45, 30), at(45, 120)],
                                    tags: ["highway": "primary", "name": "North East Road"]))
        let r = resolve(ways: ways, exitDeg: 90, router: 3)
        // West, north, north-east, east: the route takes the 4th.
        XCTAssertEqual(r.exit, 4)
        XCTAssertEqual(r.eligibleExits, 4)
        XCTAssertEqual(r.source, .osmTopology)
    }

    func testPrivateArmIsRejectedAndNotCounted() {
        var ways = fourArm()
        ways.append(Roundabouts.Way(id: 320, nodes: [2, 92], points: [at(45, 30), at(45, 120)],
                                    tags: ["highway": "service", "access": "private", "name": "Private drive"]))
        let r = resolve(ways: ways, exitDeg: 90, router: 3)
        XCTAssertEqual(r.exit, 3, "the private drive is not a usable exit")
        XCTAssertEqual(r.eligibleExits, 3)
        XCTAssertTrue(r.rejected.contains { $0.contains("way 320") && $0.contains("access=private") })
    }

    func testFiveExitsOnTheCircleKeepTheirOrder() {
        var ways = fourArm()
        for (i, deg) in [45.0, 135.0].enumerated() {
            ways.append(Roundabouts.Way(id: Int64(330 + i), nodes: [Int64([2, 5][i]), Int64(93 + i)],
                                        points: [at(deg, 30), at(deg, 120)],
                                        tags: ["highway": "primary", "name": "Extra \(i)"]))
        }
        let r = resolve(ways: ways, exitDeg: 90, router: 3)
        // West, north, north-east, east, south-east: east is still the 4th ahead.
        XCTAssertEqual(r.exit, 4)
        XCTAssertEqual(r.eligibleExits, 5)
        XCTAssertEqual(r.shape?.exits.count, 5)
    }

    func testResolvedRouteKeepsNumberWordsAndPictureTogether() throws {
        let ways = fourArm()
        let r = route(exitDeg: 90)
        var m = Maneuver(type: .roundabout, instruction: "At the roundabout, take the 2nd exit",
                         location: at(180, 30), alongMeters: r.along, distanceMeters: 300, exit: 2)
        m.routerExit = 2
        var off = Maneuver(type: .roundabout, instruction: "Exit the roundabout",
                           location: at(90, 30), alongMeters: r.along + 120, distanceMeters: 0)
        off.leavesRoundabout = true
        let route = Route(mode: .drive, polyline: r.line, distanceMeters: 600, typicalSeconds: 60,
                          trafficSeconds: nil, summary: nil, maneuvers: [m, off], source: "osm")
        let out = try XCTUnwrap(Roundabouts.resolved(route, ways: ways, clockwise: true))
        let on = out.maneuvers[0], leaving = out.maneuvers[1]
        XCTAssertEqual(on.exit, 3)
        XCTAssertEqual(on.instruction, "At the roundabout, take the 3rd exit")
        XCTAssertEqual(on.exitSource, .osmTopology)
        XCTAssertEqual(on.roundabout?.taken, 2)
        // The way off carries the same number and words, so no view can disagree.
        XCTAssertEqual(leaving.exit, 3)
        XCTAssertEqual(leaving.roundabout, on.roundabout)
        XCTAssertEqual(leaving.exitSource, .osmTopology)
    }

    func testDiagnosticsNameEverySource() {
        let r = resolve(ways: fourArm(), exitDeg: 90, router: 2)
        let text = RoundaboutExitResolver.diagnostics(r).joined(separator: "\n")
        XCTAssertTrue(text.contains("router: 2"))
        XCTAssertTrue(text.contains("osm: 3"))
        XCTAssertTrue(text.contains("final: 3"))
        XCTAssertTrue(text.contains("source: osm-topology"))
    }
}

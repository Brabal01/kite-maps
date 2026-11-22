import XCTest
@testable import VelaCore

final class GPSReplayTests: XCTestCase {
    /// An L-shaped road: 600 m north, then 400 m east.
    private let origin = LatLng(50.0, 14.0)
    private var line: [LatLng] {
        let corner = LatLng(origin.lat + 600 / 110_540, origin.lng)
        let end = LatLng(corner.lat, corner.lng + 400 / (111_320 * cos(origin.lat * .pi / 180)))
        return [origin, corner, end]
    }

    private func route() -> Route {
        let l = line
        let length = Geo.length(l)
        return Route(mode: .drive, polyline: l, distanceMeters: length, typicalSeconds: length / 13,
                     maneuvers: [Maneuver(type: .depart, instruction: "Head north", location: l[0], alongMeters: 0, distanceMeters: 600),
                                 Maneuver(type: .turnRight, instruction: "Turn right", location: l[1], alongMeters: 600, distanceMeters: 400),
                                 Maneuver(type: .arrive, instruction: "Arrive", location: l[2], alongMeters: length, distanceMeters: 0)],
                     source: "test")
    }

    func testGeneratedDriveFollowsTheRoadAtTheRequestedSpeed() throws {
        let fixture = GPSReplayFixture.drive(along: line, speed: 10, interval: 1)
        XCTAssertEqual(fixture.duration, 100, accuracy: 1.5)
        XCTAssertEqual(fixture.fixes.first?.speed, 10)
        XCTAssertEqual(fixture.fixes.last?.speed, 0, "the drive ends stopped")
        let courseNorth = try XCTUnwrap(fixture.fixes[5].course)
        XCTAssertEqual(courseNorth, 0, accuracy: 1)
        let courseEast = try XCTUnwrap(fixture.fixes[80].course)
        XCTAssertEqual(courseEast, 90, accuracy: 1)
        let end = fixture.coordinate(of: try XCTUnwrap(fixture.fixes.last))
        XCTAssertLessThan(end.distance(to: line[2]), 2)
    }

    func testFixtureRoundTripsAndRejectsGarbage() throws {
        let fixture = GPSReplayFixture.drive(along: line, speed: 10, interval: 5, name: "L road")
        let decoded = try XCTUnwrap(GPSReplayFixture.decode(fixture.encoded()))
        XCTAssertEqual(decoded, fixture)
        XCTAssertNil(GPSReplayFixture.decode(Data("{}".utf8)))
        var wrongSchema = fixture; wrongSchema.schema = "other"
        XCTAssertNil(GPSReplayFixture.decode(wrongSchema.encoded()))
        var unordered = fixture; unordered.fixes.swapAt(1, 2)
        XCTAssertNil(GPSReplayFixture.decode(unordered.encoded()), "timestamps must not go backwards")
    }

    func testTheSameSeedGivesTheSameNoise() {
        let fixture = GPSReplayFixture.drive(along: line, speed: 10)
        var options = GPSReplayOptions(); options.noiseMeters = 6; options.seed = 42
        XCTAssertEqual(GPSReplayPlan.schedule(fixture, options: options), GPSReplayPlan.schedule(fixture, options: options))
        options.seed = 43
        XCTAssertNotEqual(GPSReplayPlan.schedule(fixture, options: options),
                          GPSReplayPlan.schedule(fixture, options: GPSReplayOptions()))
    }

    func testDropoutRemovesFixesAndLateFixesArriveAfterNewerOnes() {
        let fixture = GPSReplayFixture.drive(along: line, speed: 10)
        var options = GPSReplayOptions()
        options.dropouts = [20...30]
        options.lateRanges = [40...41]
        options.lateBySeconds = 4
        let plan = GPSReplayPlan.schedule(fixture, options: options)
        XCTAssertFalse(plan.contains { (20...30).contains($0.fix.t) })
        let late = plan.firstIndex { $0.fix.t == 40 }!
        let newer = plan.firstIndex { $0.fix.t == 43 }!
        XCTAssertGreaterThan(late, newer - 1, "the 40 s fix is delivered at 44 s, after the 43 s fix")
        XCTAssertTrue(plan[late].isLate)
        XCTAssertEqual(plan.map(\.deliverAt), plan.map(\.deliverAt).sorted())
    }

    /// The tracker, fed a noisy drive with a tunnel, must keep a monotonic position and arrive.
    func testTrackerSurvivesNoiseAndATunnel() {
        let r = route()
        let fixture = GPSReplayFixture.drive(along: line, speed: 10)
        var options = GPSReplayOptions()
        options.noiseMeters = 5
        options.dropouts = [30...38]
        let tracker = RouteTracker(route: r)
        var previous = 0.0
        var arrived = false
        let start = Date(timeIntervalSince1970: 1_000_000)
        for step in GPSReplayPlan.schedule(fixture, options: options) {
            let progress = tracker.update(step.coordinate, accuracy: step.fix.accuracy,
                                          heading: step.fix.course >= 0 ? step.fix.course : nil,
                                          speed: max(0, step.fix.speed), now: start.addingTimeInterval(step.deliverAt))
            XCTAssertGreaterThanOrEqual(progress.alongMeters, previous - 15, "progress must not jump backwards at \(step.fix.t) s")
            previous = max(previous, progress.alongMeters)
            if progress.arrived { arrived = true }
        }
        XCTAssertGreaterThan(previous, 950, "the whole 1000 m was followed")
        XCTAssertTrue(arrived || previous > 975)
    }

    /// A single wild fix must not be taken as leaving the route.
    func testASinglePoorFixDoesNotTriggerOffRoute() {
        let r = route()
        let fixture = GPSReplayFixture.drive(along: line, speed: 10)
        var options = GPSReplayOptions()
        options.poorRanges = [25...25]
        let tracker = RouteTracker(route: r)
        let start = Date(timeIntervalSince1970: 1_000_000)
        var offRouteFixes = 0
        for step in GPSReplayPlan.schedule(fixture, options: options) {
            let progress = tracker.update(step.coordinate, accuracy: step.fix.accuracy,
                                          heading: step.fix.course >= 0 ? step.fix.course : nil,
                                          speed: max(0, step.fix.speed), now: start.addingTimeInterval(step.deliverAt))
            if progress.offRouteFixes >= 3 { offRouteFixes += 1 }
        }
        XCTAssertEqual(offRouteFixes, 0)
    }
}

final class GoldenNavigationFixtureTests: XCTestCase {
    private func fixture(_ name: String) throws -> GPSReplayFixture {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).json")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(GPSReplayFixture.decode(data), "\(name) stopped decoding")
    }

    func testFourExitRoundaboutFixtureDrivesTheWholeRoute() throws {
        let f = try fixture("four_exit_roundabout")
        let line = try XCTUnwrap(f.routePolyline)
        XCTAssertEqual(f.name, "four-exit roundabout")
        XCTAssertGreaterThan(line.count, 5)
        let route = Route(mode: .drive, polyline: line, distanceMeters: Geo.length(line), typicalSeconds: 90,
                          maneuvers: [Maneuver(type: .roundabout, instruction: "Take the 2nd exit",
                                               location: line[3], alongMeters: 240, distanceMeters: 100, exit: 2),
                                      Maneuver(type: .arrive, instruction: "Arrive", location: line.last!,
                                               alongMeters: Geo.length(line), distanceMeters: 0)], source: "golden")
        let tracker = RouteTracker(route: route)
        var last = 0.0
        let start = Date(timeIntervalSince1970: 40_000)
        for step in GPSReplayPlan.schedule(f) {
            let p = tracker.update(step.coordinate, accuracy: step.fix.accuracy,
                                   heading: step.fix.course >= 0 ? step.fix.course : nil,
                                   speed: max(0, step.fix.speed), now: start.addingTimeInterval(step.deliverAt))
            XCTAssertGreaterThanOrEqual(p.alongMeters, last - 15, "the roundabout must not move the arrow backwards")
            last = max(last, p.alongMeters)
        }
        XCTAssertGreaterThan(last, Geo.length(line) * 0.9)
        XCTAssertEqual(route.maneuvers[0].exit, 2, "the golden scenario fixes the expected instruction")
    }

    func testTunnelFixtureHasARealGap() throws {
        let f = try fixture("tunnel")
        let fixes = Set(f.fixes.map(\.t))
        XCTAssertTrue(Array(stride(from: 20.0, through: 35.0, by: 1.0)).contains { !fixes.contains($0) }, "the fixture actually drops fixes in the tunnel")
    }

    func testWrongTurnFixtureIsNotMistakenForARerouteSignal() throws {
        let f = try fixture("wrong_turn")
        let line = try XCTUnwrap(f.routePolyline)
        let route = Route(mode: .drive, polyline: line, distanceMeters: Geo.length(line), typicalSeconds: 90,
                          maneuvers: [], source: "golden")
        let tracker = RouteTracker(route: route)
        var consecutive = 0
        for step in GPSReplayPlan.schedule(f) {
            let p = tracker.update(step.coordinate, accuracy: step.fix.accuracy,
                                   speed: max(0, step.fix.speed), now: Date(timeIntervalSince1970: 50_000).addingTimeInterval(step.deliverAt))
            consecutive = p.offRouteFixes
            XCTAssertLessThan(consecutive, 3, "one shifted stretch must not become a confirmed departure")
        }
    }

    func testCorruptFixtureIsRejected() throws {
        let f = try fixture("tunnel")
        var broken = f; broken.schema = "different"
        XCTAssertNil(GPSReplayFixture.decode(broken.encoded()))
    }
    func testIncidentReplaysExitSignalDirectionAndAnInaccurateJump() throws {
        let origin = LatLng(50, 14)
        let turn = LatLng(50.002, 14)
        let end = LatLng(50.004, 14)
        let length = Geo.length([origin, turn, end])
        let route = Route(mode: .drive, polyline: [origin, turn, end], distanceMeters: length,
                          typicalSeconds: 30, maneuvers: [
            Maneuver(type: .roundabout, instruction: "Take the wrong third exit", location: turn,
                     alongMeters: origin.distance(to: turn), distanceMeters: 150, exit: 3)
        ], source: "test")
        let fixture = GPSReplayFixture(name: "Roundabout and signal", origin: origin, fixes: [
            .init(t: 0, east: 0, north: 0, speed: 10, course: 0),
            .init(t: 1, east: 0, north: 10, speed: 10, course: 0),
            .init(t: 2, east: 200, north: 300, accuracy: 80, speed: 10, course: 0)
        ])
        let incident = NavigationReplayIncident(route: OfflineRouteSnapshot(route), gps: fixture,
            signalCandidates: [
                .init(location: turn, alongMeters: 220, directionCertain: true, ambiguous: false),
                .init(location: turn, alongMeters: 225, directionCertain: false, ambiguous: true)
            ], observed: .init(instruction: "Wrong", roundaboutExit: 3, trafficLights: 2, offRoute: false),
            expectedRoundaboutExit: 2, expectedTrafficLights: 1)
        let encoded = try JSONEncoder().encode(incident)
        let imported = try XCTUnwrap(NavigationReplayIncident.decode(encoded))
        let replayed = try XCTUnwrap(imported.replay())
        XCTAssertEqual(replayed.roundaboutExit, 3, "The wrong exit can be reproduced for a regression fixture")
        XCTAssertNotEqual(replayed.roundaboutExit, imported.expectedRoundaboutExit)
        XCTAssertEqual(replayed.trafficLights, imported.expectedTrafficLights)
        XCTAssertFalse(replayed.offRoute, "A poor-accuracy GPS jump must not replace the current instruction")
        XCTAssertNil(NavigationReplayIncident.decode(Data("{\"schema\":\"unknown\"}".utf8)))
    }

}

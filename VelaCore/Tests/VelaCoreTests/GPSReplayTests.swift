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

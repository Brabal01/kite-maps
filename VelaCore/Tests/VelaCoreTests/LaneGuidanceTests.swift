import XCTest
@testable import VelaCore

final class LaneGuidanceTests: XCTestCase {
    private func maneuver(_ type: ManeuverType, lanes: [Lane], at meters: Double = 300,
                          roundabout: RoundaboutShape? = nil, exit: Int? = nil) -> Maneuver {
        Maneuver(type: type, instruction: "Turn", location: LatLng(50, -1),
                 alongMeters: meters, distanceMeters: 200, lanes: lanes, exit: exit,
                 roundabout: roundabout)
    }

    func testMotorwayExitLightsTheExitLanesAndKeepsTheOtherOneDim() {
        let m = maneuver(.rampRight, lanes: [
            Lane(indications: ["straight"], valid: false),
            Lane(indications: ["straight", "slight right"], valid: true),
            Lane(indications: ["slight right"], valid: true)
        ])
        let guide = LaneGuidanceEngine.guide(for: m, distance: 260, speed: 28,
                                             offRoute: false, leftTraffic: false)
        XCTAssertEqual(guide?.kind, .motorwayExit)
        XCTAssertEqual(guide?.recommended, [1, 2])
        XCTAssertEqual(guide?.lanes[0].use, .unsuitable)
    }

    func testStraightOnIsShownOnlyForARealJunctionAhead() {
        let m = maneuver(.straight, lanes: [
            Lane(indications: ["straight"], valid: true),
            Lane(indications: ["straight"], valid: true)
        ])
        XCTAssertNil(LaneGuidanceEngine.guide(for: m, distance: 150, speed: 12,
                                              offRoute: false, leftTraffic: false))
        let then = maneuver(.turnRight, lanes: [], at: 480)
        let guide = LaneGuidanceEngine.guide(for: m, distance: 150, speed: 12,
                                             offRoute: false, leftTraffic: false,
                                             next: then, nextDistance: 120)
        XCTAssertEqual(guide?.kind, .straight)
        XCTAssertTrue(guide?.showEarly == true)
    }

    func testSplitOffersTheStraightFallbackAsSuitableNotRecommended() {
        let m = maneuver(.forkRight, lanes: [
            Lane(indications: ["straight"], valid: false),
            Lane(indications: ["slight right"], valid: false),
            Lane(indications: ["right"], valid: false)
        ])
        let guide = LaneGuidanceEngine.guide(for: m, distance: 200, speed: 20,
                                             offRoute: false, leftTraffic: false)
        XCTAssertEqual(guide?.lanes[0].use, .suitable)
        XCTAssertEqual(guide?.lanes[2].use, .recommended)
    }

    func testAllUnknownLanesNeverInventARecommendation() {
        let m = maneuver(.turnLeft, lanes: [
            Lane(indications: [], valid: false),
            Lane(indications: [], valid: false)
        ])
        XCTAssertNil(LaneGuidanceEngine.guide(for: m, distance: 100, speed: 10,
                                              offRoute: false, leftTraffic: false))
    }

    func testRoundaboutRuleLanesRespectLeftTraffic() {
        var shape = RoundaboutShape(exits: [180, 90, 270, 0], taken: 2,
                                    clockwise: true, complete: true)
        shape.entryLanes = 3
        let m = maneuver(.roundabout, lanes: [], roundabout: shape, exit: 3)
        let left = LaneGuidanceEngine.guide(for: m, distance: 250, speed: 15,
                                            offRoute: false, leftTraffic: true)
        let right = LaneGuidanceEngine.guide(for: m, distance: 250, speed: 15,
                                             offRoute: false, leftTraffic: false)
        XCTAssertEqual(left?.kind, .roundabout)
        XCTAssertEqual(right?.kind, .roundabout)
        XCTAssertFalse(left?.recommended.isEmpty ?? true)
        XCTAssertFalse(right?.recommended.isEmpty ?? true)
        XCTAssertNotEqual(left?.recommended, right?.recommended)
    }

    func testNoStripOffRouteOrBeyondTheLead() {
        let m = maneuver(.rampRight, lanes: [
            Lane(indications: ["straight"], valid: false),
            Lane(indications: ["right"], valid: true)
        ])
        XCTAssertNil(LaneGuidanceEngine.guide(for: m, distance: 50, speed: 30,
                                              offRoute: true, leftTraffic: false))
        XCTAssertNil(LaneGuidanceEngine.guide(for: m, distance: 10_000, speed: 30,
                                              offRoute: false, leftTraffic: false))
    }
}

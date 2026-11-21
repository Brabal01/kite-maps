import XCTest
@testable import VelaCore

final class JunctionGuideTests: XCTestCase {
    private func sign(_ number: String?, _ refs: [String], _ destinations: [String]) -> ExitSign {
        ExitSign(number: number, references: refs, destinations: destinations)
    }

    private func exit(_ type: ManeuverType, sign: ExitSign?, lanes: [Lane],
                      instruction: String = "Take the exit") -> Maneuver {
        var m = Maneuver(type: type, instruction: instruction, location: LatLng(51.5, -0.1),
                         alongMeters: 900, distanceMeters: 300, lanes: lanes)
        m.exitSign = sign
        return m
    }

    func testRightHandMotorwayExitDrawsTakenBranchAndRealSignedDestinations() {
        let m = exit(.rampRight,
                     sign: sign("8", ["M40"], ["Oxford", "Bicester"]),
                     lanes: [Lane(indications: ["straight"], valid: false),
                             Lane(indications: ["slight right"], valid: true),
                             Lane(indications: ["right"], valid: true)])
        let guide = JunctionGuideBuilder.guide(for: m, distance: 400, speed: 30,
                                               leftTraffic: false)
        XCTAssertEqual(guide?.exitNumber, "8")
        XCTAssertEqual(guide?.destinations, ["Oxford", "Bicester"])
        XCTAssertEqual(guide?.takenBranch, 1)
        XCTAssertEqual(guide?.branches[1].isTaken, true)
        XCTAssertEqual(guide?.recommendedLanes, [1, 2])
        XCTAssertEqual(guide?.isMotorway, true)
        XCTAssertGreaterThanOrEqual(guide?.confidence ?? 0, 0.9)
    }

    func testLeftHandTrafficKeepsTheVisualSideConsistent() {
        let m = exit(.forkLeft,
                     sign: sign(nil, ["A34"], ["Newbury"]),
                     lanes: [Lane(indications: ["left"], valid: true),
                             Lane(indications: ["straight"], valid: false)])
        let guide = JunctionGuideBuilder.guide(for: m, distance: 220, speed: 22,
                                               leftTraffic: true)
        XCTAssertEqual(guide?.takenBranch, 0)
        XCTAssertEqual(guide?.branches[0].isTaken, true)
        XCTAssertEqual(guide?.branches[1].label, "Keep right")
    }

    func testInsufficientDataProducesNoMisleadingDiagram() {
        let m = exit(.rampRight, sign: nil, lanes: [],
                     instruction: "Take the exit")
        XCTAssertNil(JunctionGuideBuilder.guide(for: m, distance: 200, speed: 20,
                                                leftTraffic: false))
    }

    func testCityTurnAndRoundaboutDoNotGetAMotorwayDiagram() {
        let turn = exit(.turnRight, sign: sign("2", ["A1"], ["Town"]),
                        lanes: [Lane(indications: ["right"], valid: true)])
        XCTAssertNil(JunctionGuideBuilder.guide(for: turn, distance: 100, speed: 10,
                                                leftTraffic: false))
        let roundabout = exit(.roundabout, sign: sign("4", ["A4"], ["Bath"]),
                              lanes: [Lane(indications: ["right"], valid: true)])
        XCTAssertNil(JunctionGuideBuilder.guide(for: roundabout, distance: 200, speed: 15,
                                                leftTraffic: false))
    }

    func testNextManeuverIsCarriedForTheFollowUp() {
        let m = exit(.rampRight, sign: sign("9", ["M6"], ["Coventry"]),
                     lanes: [Lane(indications: ["right"], valid: true),
                             Lane(indications: ["straight"], valid: false)])
        let next = Maneuver(type: .roundabout, instruction: "At the roundabout take the second exit",
                            location: LatLng(51.5, -0.1), alongMeters: 1_200, distanceMeters: 200, exit: 2)
        let guide = JunctionGuideBuilder.guide(for: m, distance: 300, speed: 25,
                                               leftTraffic: false, next: next, nextDistance: 120)
        XCTAssertEqual(guide?.nextInstruction, "At the roundabout take the second exit")
        XCTAssertEqual(guide?.exitNumber, "9")
    }

    func testRoadNumbersAreExtractedWithoutInventingOne() {
        XCTAssertEqual(RoadReferenceParser.find("Take the M25 then the A3"), ["M25", "A3"])
        XCTAssertTrue(RoadReferenceParser.find("Turn left onto the High Street").isEmpty)
    }
}

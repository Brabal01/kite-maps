import XCTest
@testable import VelaCore

final class TransitGuidanceTests: XCTestCase {
    private func fix(_ meters: Double, north: Double = 0) -> LatLng {
        LatLng(49.595 + north / 111_195, 17.25 + meters / 72_074)
    }

    private func time(_ seconds: Double) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + seconds)
    }

    private func call(_ name: String, at location: LatLng, time seconds: Double? = nil,
                      cancelled: Bool = false) -> TransitCall {
        TransitCall(id: name, name: name, location: location, arrival: seconds.map(time),
                    departure: nil, platform: nil, arrivalDelay: nil, departureDelay: nil, cancelled: cancelled)
    }

    func testBoardingNeedsStopVisitAndTwoOrderedForwardFixes() {
        var tracker = TransitBoarding(path: [fix(0), fix(440), fix(1_000)], stop: fix(0))
        func sample(_ meters: Double, _ seconds: Double, speed: Double = 12, course: Double = 90,
                    accuracy: Double = 15, north: Double = 0) -> Bool {
            tracker.observe(fix(meters, north: north), accuracy: accuracy, speed: speed, course: course,
                            at: time(seconds), departure: time(0))
        }
        XCTAssertFalse(sample(100, -20))
        XCTAssertFalse(sample(160, -15))
        XCTAssertFalse(sample(0, -5, speed: 0))
        XCTAssertFalse(sample(120, 1, course: 270))
        XCTAssertFalse(sample(155, 2, north: 42))
        XCTAssertFalse(sample(175, 3, accuracy: 60))
        XCTAssertFalse(sample(200, 5))
        XCTAssertFalse(sample(235, 5))
        XCTAssertFalse(sample(245, 5.4))
        XCTAssertTrue(sample(270, 8))
    }

    func testBoardingRejectsExpiredVisitAndEarlyDeparture() {
        var tracker = TransitBoarding(path: [fix(0), fix(1_000)], stop: fix(0))
        XCTAssertFalse(tracker.observe(fix(0), accuracy: 10, speed: 0, course: -1, at: time(-220), departure: time(0)))
        XCTAssertFalse(tracker.observe(fix(100), accuracy: 10, speed: 8, course: -1, at: time(-112), departure: time(0)))
        XCTAssertFalse(tracker.observe(fix(140), accuracy: 10, speed: 8, course: -1, at: time(-102), departure: time(0)))
        XCTAssertFalse(tracker.observe(fix(180), accuracy: 10, speed: 8, course: -1, at: time(10), departure: time(0)))
        XCTAssertFalse(tracker.observe(fix(220), accuracy: 10, speed: 8, course: -1, at: time(15), departure: time(0)))
    }

    func testRidingKeepsOrderAtRepeatedCrossingAndWaitsForExitEvidence() throws {
        let crossing = fix(400)
        let turn = fix(700, north: 450)
        let exit = fix(850)
        let line = [fix(0), crossing, turn, crossing, exit]
        var leg = TransitLeg(isWalk: false, mode: "TRAM", path: line)
        leg.calls = [call("Start", at: line[0]), call("First crossing", at: crossing),
                     call("Turn", at: turn), call("Second crossing", at: crossing), call("Exit", at: exit)]
        var tracker = TransitRide(leg: leg)
        XCTAssertNil(tracker.observe(turn, accuracy: 100, speed: 8, at: time(1)))
        XCTAssertNil(tracker.observe(fix(400, north: -160), accuracy: 20, speed: 8, at: time(2)))
        XCTAssertEqual(tracker.nextIndex, 1)
        XCTAssertNotNil(tracker.observe(crossing, accuracy: 70, speed: 8, at: time(5)))
        XCTAssertEqual(tracker.nextIndex, 2)
        XCTAssertNotNil(tracker.observe(turn, accuracy: 30, speed: 8, at: time(35)))
        XCTAssertEqual(tracker.nextIndex, 3)
        XCTAssertNotNil(tracker.observe(crossing, accuracy: 30, speed: 8, at: time(65)))
        XCTAssertEqual(tracker.nextIndex, 4)
        let approach = try XCTUnwrap(tracker.observe(fix(700), accuracy: 25, speed: 12, at: time(90)))
        XCTAssertTrue(approach.exitApproach)
        XCTAssertFalse(approach.readyToExit)
        XCTAssertFalse(try XCTUnwrap(tracker.observe(exit, accuracy: 30, speed: 2, at: time(110))).readyToExit)
        XCTAssertNil(tracker.observe(exit, accuracy: 30, speed: 2, at: time(110)))
        XCTAssertTrue(try XCTUnwrap(tracker.observe(exit, accuracy: 30, speed: 2, at: time(113))).readyToExit)
    }

    func testTimetableDoesNotRewindGpsAndSkipsCancelledCalls() {
        var leg = TransitLeg(isWalk: false, mode: "BUS", path: [fix(0), fix(300), fix(600), fix(850)])
        leg.calls = [call("Start", at: fix(0)), call("Passed but delayed", at: fix(300), time: 900),
                     call("Skipped", at: fix(600), time: 600, cancelled: true),
                     call("Exit undated", at: fix(850))]
        var tracker = TransitRide(leg: leg)
        XCTAssertNotNil(tracker.observe(fix(300), accuracy: 15, speed: 8, at: time(100)))
        XCTAssertEqual(tracker.nextIndex, 2)
        XCTAssertEqual(tracker.scheduledNext(in: leg.calls, at: time(110))?.name, "Exit undated")
        XCTAssertEqual(tracker.lastPositionAt, time(100))
    }

    func testTransitousParsesStopCancellationAndCancelsLegAtEndpoints() throws {
        let json = """
        {"itineraries":[{"legs":[{"mode":"BUS",
          "from":{"name":"A","lat":49.59,"lon":17.25},
          "intermediateStops":[{"name":"B","lat":49.60,"lon":17.25,"cancelled":true}],
          "to":{"name":"C","lat":49.61,"lon":17.25,"cancelled":true}}]}]}
        """
        let leg = try XCTUnwrap(Transitous.parse(Data(json.utf8)).first?.legs.first)
        XCTAssertEqual(leg.calls.map(\.cancelled), [false, true, true])
        XCTAssertTrue(leg.cancelled)
    }
}

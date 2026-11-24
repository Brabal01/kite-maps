import XCTest
@testable import VelaCore

final class BoardingDetectorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)
    /// A tram line running north for 2 km.
    private let line = [LatLng(50.0, 14.0), LatLng(50.01, 14.0), LatLng(50.02, 14.0)]

    private func point(along meters: Double, sideways: Double = 0) -> LatLng {
        LatLng(50.0 + meters / 110_540, 14.0 + sideways / (111_320 * cos(50 * .pi / 180)))
    }

    private func sample(_ seconds: Double, along: Double, sideways: Double = 0, speed: Double, course: Double = 0, accuracy: Double = 8) -> BoardingDetector.Sample {
        .init(time: t0.addingTimeInterval(seconds), location: point(along: along, sideways: sideways), accuracy: accuracy, speed: speed, course: course)
    }

    /// Waits at the stop, then rides north at 10 m/s.
    private func ride(from detector: inout BoardingDetector, departure: Date?, sideways: Double = 0, course: Double = 0, skipStop: Bool = false, vehicle: LatLng? = nil) -> [BoardingDetector.Decision] {
        var decisions: [BoardingDetector.Decision] = []
        if !skipStop {
            for second in stride(from: -60.0, to: 0, by: 20) {
                decisions.append(detector.observe(sample(second, along: 5, speed: 0, course: -1), line: line, departure: departure))
            }
        }
        for second in 0..<30 {
            let along = 10.0 + Double(second) * 10
            decisions.append(detector.observe(sample(Double(second), along: along, sideways: sideways, speed: 10, course: course),
                                              line: line, departure: departure, vehicle: vehicle))
        }
        return decisions
    }

    func testBoardsAfterWaitingAtTheStopAndRidingAlongTheLine() {
        var detector = BoardingDetector()
        let decisions = ride(from: &detector, departure: t0)
        XCTAssertTrue(decisions.contains(.boarded))
        let first = decisions.firstIndex(of: .boarded)!
        XCTAssertGreaterThan(first, 8, "needs several fixes and 120 m, never the first fast fix")
    }

    func testACarDrivingBesideTheLineNeverWaitedAtTheStop() {
        var detector = BoardingDetector()
        let decisions = ride(from: &detector, departure: t0, skipStop: true)
        XCTAssertFalse(decisions.contains(.boarded))
    }

    func testMovingAwayFromTheLineOrAgainstItDoesNotBoard() {
        var far = BoardingDetector()
        XCTAssertFalse(ride(from: &far, departure: t0, sideways: 120).contains(.boarded), "120 m off the line")
        var wrongWay = BoardingDetector()
        XCTAssertFalse(ride(from: &wrongWay, departure: t0, course: 180).contains(.boarded), "heading south on a northbound line")
    }

    func testWalkingSpeedIsNotARide() {
        var detector = BoardingDetector()
        var boarded = false
        for second in 0..<200 {
            if detector.observe(sample(Double(second), along: 5 + Double(second) * 1.4, speed: 1.4), line: line, departure: t0) == .boarded { boarded = true }
        }
        XCTAssertFalse(boarded)
    }

    func testTheLiveVehicleMustBeNearby() {
        var detector = BoardingDetector()
        let somewhereElse = LatLng(50.0, 14.5)
        XCTAssertFalse(ride(from: &detector, departure: t0, vehicle: somewhereElse).contains(.boarded))
        var near = BoardingDetector()
        XCTAssertTrue(ride(from: &near, departure: t0, vehicle: point(along: 600)).contains(.boarded) ||
                      ride(from: &near, departure: t0, vehicle: point(along: 200)).contains(.boarded))
    }

    func testAPoorFixIsIgnored() {
        var detector = BoardingDetector()
        XCTAssertEqual(detector.observe(sample(0, along: 5, speed: 0, accuracy: 120), line: line, departure: t0), .notYet)
    }

    func testAnEarlierSightingHoursBeforeDepartureDoesNotCount() {
        var detector = BoardingDetector()
        // Seen at the stop two hours before the departure, then a car passes later.
        _ = detector.observe(.init(time: t0.addingTimeInterval(-7200), location: point(along: 5), accuracy: 8, speed: 0, course: -1),
                             line: line, departure: t0)
        var decisions: [BoardingDetector.Decision] = []
        for second in 0..<30 {
            decisions.append(detector.observe(sample(Double(second), along: 10 + Double(second) * 10, speed: 10), line: line, departure: t0))
        }
        XCTAssertFalse(decisions.contains(.boarded))
    }
}

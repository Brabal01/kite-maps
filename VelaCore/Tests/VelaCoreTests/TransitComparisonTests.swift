import Foundation
import XCTest
@testable import VelaCore

final class TransitComparisonTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)
    private func leg(_ a: Double, _ b: Double, _ distance: Double = 0) -> TransitLeg {
        TransitLeg(isWalk: distance > 0, mode: distance > 0 ? "WALK" : "TRAM",
                   fromName: "Origin", toName: "Destination",
                   depart: start.addingTimeInterval(a), arrive: start.addingTimeInterval(b),
                   durationSeconds: b - a, distanceMeters: distance, path: [])
    }

    private func trip(_ legs: [TransitLeg]) -> TransitTrip {
        TransitTrip(depart: start, arrive: legs.last?.arrive,
                    durationSeconds: legs.last?.arrive?.timeIntervalSince(start) ?? 0,
                    transfers: max(0, legs.filter { !$0.isWalk }.count - 1), legs: legs)
    }

    func testTimelinePreservesRideWalkAndConnectionWaitDurations() {
        let segments = TransitComparison.timeline(for: trip([leg(0, 240), leg(240, 300, 70), leg(480, 780)]))
        XCTAssertEqual(segments.map(\.kind), [.ride, .walk, .wait, .ride])
        XCTAssertEqual(segments.map(\.offset), [0, 240, 300, 480])
        XCTAssertEqual(segments.map(\.duration), [240, 60, 180, 300])
    }

    func testTransferRiskUsesActualTimesAndWalkingSpeed() {
        let route = trip([leg(0, 360), leg(360, 450, 150), leg(480, 780)])
        XCTAssertEqual(TransitComparison.transfers(for: route, walkingSpeedKmh: 3).first?.risk, .high)
        XCTAssertEqual(TransitComparison.transfers(for: route, walkingSpeedKmh: 6).first?.risk, .tight)
        XCTAssertEqual(TransitComparison.transfers(for: route, walkingSpeedKmh: 6).first?.spareSeconds, 30)
    }

    func testRecommendationAvoidsRiskyTransferDespiteEarlierArrival() {
        let trips = [trip([leg(0, 360), leg(360, 455, 150), leg(450, 720)]), trip([leg(0, 1_200)])]
        XCTAssertEqual(TransitComparison.rankedIndices(trips, by: .fastest, walkingSpeedKmh: 5), [0, 1])
        XCTAssertEqual(TransitComparison.rankedIndices(trips, by: .recommended, walkingSpeedKmh: 5), [1, 0])
        XCTAssertEqual(TransitComparison.rankedIndices(trips, by: .safestTransfers, walkingSpeedKmh: 5), [1, 0])
    }
    func testViaPlansForwardAfterTheDwellTime() async throws {
        let points = [LatLng(49.59, 17.25), LatLng(49.6, 17.27), LatLng(49.61, 17.29)]
        var requests: [Date] = []
        let options = try await Transitous.composeVia(points, time: start, arriveBy: false, dwellSeconds: 300) {
            from, to, time, backward in
            XCTAssertFalse(backward)
            XCTAssertEqual(from, points[requests.count])
            XCTAssertEqual(to, points[requests.count + 1])
            requests.append(time)
            let offset = time.timeIntervalSince(self.start)
            return [self.trip([self.leg(offset, offset + 600)])]
                .map { var candidate = $0; candidate.depart = time; return candidate }
        }
        XCTAssertEqual(requests, [start, start.addingTimeInterval(900)])
        XCTAssertEqual(options.first?.waypointLegs, [0])
        XCTAssertEqual(options.first?.durationSeconds, 1_500)
    }

    func testViaArriveByPlansBackwardBeforeTheDwellTime() async throws {
        let points = [LatLng(49.59, 17.25), LatLng(49.6, 17.27), LatLng(49.61, 17.29)]
        let arrival = start.addingTimeInterval(2_000)
        var requests: [Date] = []
        let options = try await Transitous.composeVia(points, time: arrival, arriveBy: true, dwellSeconds: 300) {
            from, to, time, backward in
            XCTAssertTrue(backward)
            XCTAssertEqual(from, points[1 - requests.count])
            XCTAssertEqual(to, points[2 - requests.count])
            requests.append(time)
            let offset = time.timeIntervalSince(self.start)
            var candidate = self.trip([self.leg(offset - 600, offset)])
            candidate.depart = time.addingTimeInterval(-600)
            return [candidate]
        }
        XCTAssertEqual(requests, [arrival, arrival.addingTimeInterval(-900)])
        XCTAssertEqual(options.first?.waypointLegs, [0])
        XCTAssertEqual(options.first?.arrive, arrival)
    }
}

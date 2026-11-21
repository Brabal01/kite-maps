import XCTest
@testable import VelaCore

/// Talks to the real Transitous service. Opt-in with KITE_VERIFY_TRANSITOUS=1; once opted in, an unreachable
/// service FAILS the test instead of skipping it, so a green run always means the live data was read.
final class TransitousLiveTests: XCTestCase {
    private var enabled: Bool { ProcessInfo.processInfo.environment["KITE_VERIFY_TRANSITOUS"] == "1" }

    private let muzeum = LatLng(50.0791, 14.4306)
    private let vltavska = LatLng(50.1003, 14.4388)

    override func setUpWithError() throws {
        try XCTSkipUnless(enabled, "Live Transitous checks are opt-in (KITE_VERIFY_TRANSITOUS=1)")
    }

    func testLivePlanBetweenTwoPragueStopsHasRealRides() async throws {
        let trips: [TransitTrip]
        do { trips = try await Transitous.plan(from: muzeum, to: vltavska) }
        catch { return XCTFail("Transitous did not answer the plan request: \(error)") }
        XCTAssertFalse(trips.isEmpty, "no trips returned")
        let trip = try XCTUnwrap(trips.first)
        let rides = trip.rides
        XCTAssertFalse(rides.isEmpty, "the first trip has no ride")
        for ride in rides {
            XCTAssertFalse(ride.line.isEmpty, "a ride without a line name")
            XCTAssertFalse(ride.path.isEmpty, "a ride without geometry")
            XCTAssertNotNil(ride.depart)
            XCTAssertNotNil(ride.arrive)
            XCTAssertFalse(ride.fromName.isEmpty)
        }
        XCTAssertGreaterThan(trip.durationSeconds, 120)
        XCTAssertLessThan(trip.durationSeconds, 3 * 3600)
    }

    func testLiveRouteMapReturnsPragueMetroWithOfficialStyleColours() async throws {
        let lines = await Transitous.lines(south: 50.04, west: 14.36, north: 50.12, east: 14.52, zoom: 12)
        let found = try XCTUnwrap(lines, "Transitous did not answer the route map request")
        XCTAssertFalse(found.isEmpty)
        XCTAssertTrue(found.contains { $0.metro || $0.mode == .metro || $0.mode == .subway },
                      "no metro line in central Prague")
        XCTAssertTrue(found.allSatisfy { $0.points.count >= 2 })
    }

    func testLiveDeparturesNearMuseumStop() async throws {
        let board = await Transitous.departures(near: muzeum, radius: 300)
        let result = try XCTUnwrap(board, "Transitous did not answer the departures request")
        XCTAssertFalse(result.stop.isEmpty)
        XCTAssertFalse(result.departures.isEmpty, "no departures at a busy central stop")
    }
}

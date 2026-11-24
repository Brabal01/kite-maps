import XCTest
@testable import VelaCore

final class AndroidTrafficDaylightTests: XCTestCase {
    func testTrafficRangesClipToPositionAndChooseWorstCongestion() {
        let spans = [TrafficSpan(level: 1, startMeters: 0, lengthMeters: 90),
                     TrafficSpan(level: 3, startMeters: 45, lengthMeters: 25),
                     TrafficSpan(level: 2, startMeters: 80, lengthMeters: 60)]
        let ranges = RouteTrafficPaint.ranges(from: 20, to: 150, traffic: spans)
        XCTAssertEqual(ranges.map(\.from), [20, 45, 70, 80, 140])
        XCTAssertEqual(ranges.map(\.to), [45, 70, 80, 140, 150])
        XCTAssertEqual(ranges.map(\.level), [1, 3, 1, 2, 0])
    }

    func testMapboxAnnotationsFollowPolylineIntervalsAcrossLegs() {
        let legs = [
            ["annotation": ["congestion": ["low", "moderate"]]],
            ["annotation": ["congestion": ["moderate", "severe"]]]
        ]
        XCTAssertEqual(MapboxRoutes.trafficSpans(legs, cumulative: [0, 15, 50, 90, 150]), [
            TrafficSpan(level: 1, startMeters: 15, lengthMeters: 75),
            TrafficSpan(level: 3, startMeters: 90, lengthMeters: 60)
        ])
        XCTAssertTrue(MapboxRoutes.trafficSpans(legs, cumulative: [0, 15]).isEmpty)
    }

    func testPragueSeasonsAndLongitudeUseLocalSunlight() throws {
        let utc = ISO8601DateFormatter()
        let prague = LatLng(50.08, 14.43)
        func date(_ timestamp: String) throws -> Date { try XCTUnwrap(utc.date(from: timestamp)) }
        XCTAssertFalse(Daylight.isDark(at: prague, time: try date("2026-06-21T18:00:00Z")))
        XCTAssertTrue(Daylight.isDark(at: prague, time: try date("2026-06-21T21:00:00Z")))
        XCTAssertFalse(Daylight.isDark(at: prague, time: try date("2026-12-21T13:00:00Z")))
        XCTAssertTrue(Daylight.isDark(at: prague, time: try date("2026-12-21T17:00:00Z")))
        let noon = try date("2026-03-20T12:00:00Z")
        XCTAssertFalse(Daylight.isDark(at: LatLng(0, 0), time: noon))
        XCTAssertTrue(Daylight.isDark(at: LatLng(0, 179), time: noon))
    }
}

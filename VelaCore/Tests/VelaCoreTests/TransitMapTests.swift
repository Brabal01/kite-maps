import Foundation
import XCTest
@testable import VelaCore

final class TransitMapTests: XCTestCase {
    func testStopIDsPreservePlatformsAndGroupStations() throws {
        let data = Data("""
        [
          {"stopId":"CZ:station:1","parentId":"CZ:station","name":"Komenského","lat":49.59,"lon":17.26},
          {"stopId":"CZ:station:2","parentId":"CZ:station","name":"Komenského","lat":49.59,"lon":17.27},
          {"stopId":"CZ:station:1","name":"Duplicate","lat":49.59,"lon":17.26},
          {"stopId":"invalid","name":"Invalid coordinate","lat":100,"lon":17}
        ]
        """.utf8)
        let stops = try Transitous.parseMapStops(data)
        XCTAssertEqual(stops.map(\.id), ["CZ:station:1", "CZ:station:2"])
        XCTAssertEqual(Set(stops.map(\.stationID)), ["CZ:station"])
        XCTAssertThrowsError(try Transitous.parseMapStops(Data("{}".utf8)))
    }

    func testBoardIdentifiesSpecificTripAndKeepsPlatformAndRealtime() throws {
        let data = Data("""
        {"stopTimes":[
          {"tripId":"20261125_16:45_cz:trip:364","routeShortName":"364","mode":"BUS",
           "realTime":true,"headsign":"Olomouc","routeColor":"1C7A42",
           "place":{"departure":"2026-11-25T16:36:00Z","scheduledDeparture":"2026-11-25T16:34:00Z",
                    "track":"2","scheduledTrack":"1"}},
          {"tripId":"scheduled","routeShortName":"2","realTime":true,
           "place":{"scheduledDeparture":"2026-11-25T16:37:00Z","departureTimestampReason":"SCHEDULE"}},
          {"tripId":"cancelled","routeShortName":"2","tripCancelled":true,
           "place":{"scheduledDeparture":"2026-11-25T16:38:00Z"}}
        ]}
        """.utf8)
        let rows = Transitous.parseStopTimes(data)
        XCTAssertEqual(rows.map(\.tripID), ["20261125_16:45_cz:trip:364", "scheduled", "cancelled"])
        XCTAssertEqual(rows.first?.delayMinutes, 2)
        XCTAssertEqual(rows.first?.platform, "2")
        XCTAssertEqual(rows.first?.color, 0x1C7A42)
        XCTAssertFalse(rows[1].isRealtime)
        XCTAssertEqual(rows.last?.isCancelled, true)
    }

    func testVehicleEstimateFollowsProviderGeometryAndStaysWithinKnownStopTimes() throws {
        let detail = try XCTUnwrap(Transitous.parseTripDetail(tripPayload(), tripID: "trip-A"))
        XCTAssertEqual(detail.calls.map(\.name), ["First", "Second", "Last"])
        XCTAssertEqual(detail.geometry.count, 3)
        let start = try XCTUnwrap(detail.calls[0].departure)
        let estimate = try XCTUnwrap(detail.position(at: start.addingTimeInterval(300)))
        XCTAssertFalse(estimate.isGPS)
        XCTAssertEqual(estimate.location.lat, (38.5 + 40.7) / 2, accuracy: 0.01)
        XCTAssertNil(detail.position(at: start.addingTimeInterval(-60)))
        XCTAssertNil(detail.position(at: start.addingTimeInterval(660)), "No estimate in the station dwell")
        XCTAssertNil(detail.position(at: start.addingTimeInterval(2000)))
        XCTAssertNil(Transitous.parseTripDetail(tripPayload(), tripID: "other-trip"))
        XCTAssertNil(Transitous.parseTripDetail(tripPayload(cancelled: true), tripID: "trip-A")?.position(at: start))
    }

    func testOnlyFreshTimestampedPositionAppearsAsGPS() throws {
        var detail = try XCTUnwrap(Transitous.parseTripDetail(tripPayload(), tripID: "trip-A"))
        let time = try XCTUnwrap(detail.calls[0].departure).addingTimeInterval(150)
        let location = LatLng(39, -121)
        detail.trip.legs[detail.legIndex].liveVehicle = TransitVehicle(location: location, updated: time)
        XCTAssertEqual(detail.position(at: time)?.location, location)
        XCTAssertEqual(detail.position(at: time)?.isGPS, true)
        XCTAssertEqual(detail.position(at: time.addingTimeInterval(121))?.isGPS, false)
        detail.trip.legs[detail.legIndex].liveVehicle?.updated = nil
        XCTAssertEqual(detail.position(at: time)?.isGPS, false)
    }

    private func tripPayload(cancelled: Bool = false) -> Data {
        Data("""
        {"legs":[{"mode":"BUS","tripId":"trip-A","cancelled":\(cancelled),
          "from":{"name":"First","lat":38.5,"lon":-120.2,"departure":"2026-11-25T16:00:00Z"},
          "intermediateStops":[
            {"name":"Second","lat":40.7,"lon":-120.95,"arrival":"2026-11-25T16:10:00Z",
             "departure":"2026-11-25T16:12:00Z"}
          ],
          "to":{"name":"Last","lat":43.252,"lon":-126.453,"arrival":"2026-11-25T16:25:00Z"},
          "legGeometry":{"points":"_p~iF~ps|U_ulLnnqC_mqNvxq`@","precision":5}}]}
        """.utf8)
    }
}

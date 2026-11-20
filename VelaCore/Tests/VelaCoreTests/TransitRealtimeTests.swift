import XCTest
@testable import VelaCore

final class TransitRealtimeTests: XCTestCase {
    private func varint(_ value: UInt64) -> [UInt8] {
        var value = value, out: [UInt8] = []
        repeat {
            var byte = UInt8(value & 0x7f)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            out.append(byte)
        } while value != 0
        return out
    }

    private func tag(_ field: Int, _ wire: Int) -> [UInt8] { varint(UInt64(field << 3 | wire)) }
    private func length(_ field: Int, _ bytes: [UInt8]) -> [UInt8] { tag(field, 2) + varint(UInt64(bytes.count)) + bytes }
    private func text(_ field: Int, _ value: String) -> [UInt8] { length(field, Array(value.utf8)) }
    private func integer(_ field: Int, _ value: Int) -> [UInt8] {
        tag(field, 0) + varint(UInt64(bitPattern: Int64(value)))
    }
    private func float(_ field: Int, _ value: Float) -> [UInt8] {
        let bits = value.bitPattern
        return tag(field, 5) + [UInt8(bits & 0xff), UInt8((bits >> 8) & 0xff),
                                UInt8((bits >> 16) & 0xff), UInt8((bits >> 24) & 0xff)]
    }

    private var tripDescriptor: [UInt8] { text(1, "trip-1") + text(5, "route-9") }

    private func feed() -> [UInt8] {
        // TripUpdate: 3 minutes late at the boarding stop.
        let event = integer(1, 180)
        let stop = text(4, "stop-1") + length(3, event)
        let update = length(1, tripDescriptor) + length(2, stop)
        let updateEntity = text(1, "update") + length(3, update)

        // VehiclePosition: Prague, pointing north at 12 m/s.
        let position = float(1, 50.08) + float(2, 14.42) + float(3, 0) + float(5, 12)
        let vehicle = length(1, tripDescriptor) + length(2, position) + integer(4, 1_800_000_000)
        let vehicleEntity = text(1, "vehicle") + length(4, vehicle)

        // Alert: a translated header, informed about the trip.
        let translation = text(1, "Detour in effect")
        let translated = length(1, translation)
        let selector = length(4, tripDescriptor)
        let alert = length(5, selector) + length(10, translated)
        let alertEntity = text(1, "alert") + length(5, alert)

        return length(2, updateEntity) + length(2, vehicleEntity) + length(2, alertEntity)
    }

    private func trip() -> TransitTrip {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var leg = TransitLeg(isWalk: false, mode: "BUS", line: "42", fromName: "Start", toName: "End",
                             depart: base, arrive: base.addingTimeInterval(600), durationSeconds: 600)
        leg.tripId = "trip-1"
        leg.routeId = "route-9"
        leg.boardStop = TransitCall(name: "Start", timeZone: nil, arrival: nil, departure: base,
                                    track: nil, scheduledTrack: nil, stopCode: nil, detail: nil,
                                    skipped: false, stopId: "stop-1")
        return TransitTrip(depart: base, arrive: base.addingTimeInterval(600), durationSeconds: 600,
                           transfers: 0, legs: [leg])
    }

    func testParsesAndAppliesGTFSRealtime() throws {
        let parsed = try XCTUnwrap(TransitRealtime.parse(Data(feed())))
        XCTAssertEqual(parsed.tripUpdates.first?.tripId, "trip-1")
        XCTAssertEqual(parsed.tripUpdates.first?.delay, nil)
        XCTAssertEqual(parsed.tripUpdates.first?.stops.first?.departureDelay, 180)
        XCTAssertEqual(parsed.vehicles.first?.location?.lat ?? 0, 50.08, accuracy: 1e-5)
        XCTAssertEqual(parsed.vehicles.first?.bearing ?? 0, 0, accuracy: 1e-5)
        XCTAssertEqual(parsed.vehicles.first?.speedMps ?? 0, 12, accuracy: 1e-5)
        XCTAssertEqual(parsed.alerts.first?.text, "Detour in effect")

        let applied = TransitRealtime.apply(parsed, to: [trip()])
        let leg = try XCTUnwrap(applied.first?.legs.first)
        XCTAssertTrue(leg.isRealtime)
        XCTAssertEqual(leg.delayMinutes, 3)
        XCTAssertEqual(leg.arrivalDelayMinutes, 3)
        XCTAssertEqual(leg.depart, Date(timeIntervalSince1970: 1_800_000_180))
        XCTAssertEqual(leg.liveVehicle?.location.lat ?? 0, 50.08, accuracy: 1e-5)
        XCTAssertTrue(leg.serviceAlerts.contains("Detour in effect"))
    }

    func testBrokenFeedLeavesScheduleAlone() {
        XCTAssertNil(TransitRealtime.parse(Data([0x0a, 0x7f, 0x01])))
        XCTAssertEqual(TransitRealtime.apply(TransitRealtime.Feed(), to: [trip()]).first?.legs.first?.delayMinutes, nil)
    }

    func testTransitousCarriesTripIdentityAndRealtimeFlag() throws {
        let json = """
        {"itineraries":[{"legs":[
          {"mode":"BUS","routeShortName":"42","tripId":"trip-1","routeId":"route-9","realTime":true,
           "startTime":"2026-11-20T14:10:00Z","scheduledStartTime":"2026-11-20T14:08:00Z",
           "endTime":"2026-11-20T14:20:00Z","scheduledEndTime":"2026-11-20T14:18:00Z",
           "from":{"name":"A","stopId":"stop-1"},"to":{"name":"B"}}
        ]}]}
        """
        let leg = try XCTUnwrap(Transitous.parse(Data(json.utf8)).first?.legs.first)
        XCTAssertEqual(leg.tripId, "trip-1")
        XCTAssertEqual(leg.routeId, "route-9")
        XCTAssertTrue(leg.isRealtime)
        XCTAssertEqual(leg.boardStop?.stopId, "stop-1")
        XCTAssertEqual(leg.delayMinutes, 2)
    }
}
